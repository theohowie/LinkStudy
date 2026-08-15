import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, HttpClient;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/secret_store.dart';
import 'link_course.dart';
import 'scheduler_engine.dart';

/// AI 提供商。
enum AiProvider {
  deepseek,
  openai;

  String get name => switch (this) {
        AiProvider.deepseek => 'deepseek',
        AiProvider.openai => 'openai',
      };

  static AiProvider fromName(String? value) => AiProvider.values.firstWhere(
        (p) => p.name == value,
        orElse: () => AiProvider.deepseek,
      );

  String get defaultBaseUrl => switch (this) {
        AiProvider.deepseek => 'https://api.deepseek.com/v1',
        AiProvider.openai => 'https://api.openai.com/v1',
      };

  String get defaultModel => switch (this) {
        AiProvider.deepseek => 'deepseek-v4-flash',
        AiProvider.openai => 'gpt-5.6-sol',
      };

  /// 可选的模型列表（随提供商变化，UI 下拉选择）。
  List<String> get modelOptions => switch (this) {
        AiProvider.deepseek => const ['deepseek-v4-flash', 'deepseek-v4-pro'],
        AiProvider.openai => const [
            'gpt-5.6-sol',
            'gpt-5.6-terra',
            'gpt-5.6-luna',
          ],
      };
}

/// AI 排课服务配置（固定设置）。
class AiScheduleConfig {
  const AiScheduleConfig({
    required this.provider,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.windowDescription = '',
    this.timeout = const Duration(seconds: 120),
  });

  final AiProvider provider;
  final String baseUrl;
  final String apiKey;
  final String model;

  /// 每天可用时间窗的人类可读描述（如 "08:00-12:00 与 13:00-23:00"），
  /// 来自通用显示设置（开始/午休/结束），由调用方在加载配置时传入。
  final String windowDescription;
  final Duration timeout;
}

/// 学习强度（诙谐语义，休息时长由 AI 决定）。
enum StudyIntensity {
  relaxed,
  medium,
  stressed;

  String get name => switch (this) {
        StudyIntensity.relaxed => 'relaxed',
        StudyIntensity.medium => 'medium',
        StudyIntensity.stressed => 'stressed',
      };

  static StudyIntensity fromName(String? value) =>
      StudyIntensity.values.firstWhere(
        (i) => i.name == value,
        orElse: () => StudyIntensity.medium,
      );
}

/// 排课开始时间：从现在开始（今天剩余时段）或从明天开始。
enum ScheduleStartMode {
  now,
  tomorrow;

  String get name => switch (this) {
        ScheduleStartMode.now => 'now',
        ScheduleStartMode.tomorrow => 'tomorrow',
      };

  static ScheduleStartMode fromName(String? value) =>
      ScheduleStartMode.values.firstWhere(
        (m) => m.name == value,
        orElse: () => ScheduleStartMode.now,
      );
}

/// 本次排课设置（记住上次选择）。
class AiSchedulePrefs {
  const AiSchedulePrefs({
    this.intensity = StudyIntensity.medium,
    this.days = 7,
    this.notes = '',
    this.timePreference = '',
    this.startMode = ScheduleStartMode.now,
  });

  final StudyIntensity intensity;
  final int days; // 计划几天学完
  final String notes; // 备注：这段时间哪些时间已有安排
  final String timePreference; // 倾向的学习时间段；空 = 全天
  final ScheduleStartMode startMode; // 从现在开始 / 从明天开始

  Map<String, dynamic> toJson() => {
        'intensity': intensity.name,
        'days': days,
        'notes': notes,
        'timePreference': timePreference,
        'startMode': startMode.name,
      };

  factory AiSchedulePrefs.fromJson(Map<String, dynamic> json) => AiSchedulePrefs(
        intensity: StudyIntensity.fromName(json['intensity'] as String?),
        days: (json['days'] as num?)?.toInt() ?? 7,
        notes: json['notes'] as String? ?? '',
        timePreference: json['timePreference'] as String? ?? '',
        startMode: ScheduleStartMode.fromName(json['startMode'] as String?),
      );
}

/// AI 排课结果（成功：顺序 + 休息 + 思路说明）。
class AiScheduleSuccess {
  const AiScheduleSuccess({required this.ordered, required this.reason});

  final List<OrderedCourse> ordered;
  final String reason;
}

/// AI 排课失败类型。
enum AiScheduleErrorType {
  notConfigured,
  network,
  http,
  parse,
  empty,
}

/// AI 排课失败（含用户可读中文信息）。
class AiScheduleError {
  const AiScheduleError({required this.type, required this.message});

  final AiScheduleErrorType type;
  final String message;
}

sealed class AiScheduleOutcome {
  const AiScheduleOutcome();
}

class AiScheduleOutcomeSuccess extends AiScheduleOutcome {
  const AiScheduleOutcomeSuccess(this.value);
  final AiScheduleSuccess value;
}

class AiScheduleOutcomeError extends AiScheduleOutcome {
  const AiScheduleOutcomeError(this.error);
  final AiScheduleError error;
}

/// 内置"排课 Skill"（system prompt）：AI 的排课方法论与输出契约。
/// 刻意精简以减小请求体（MTU 黑洞环境下大请求会被丢弃）。
const aiScheduleSystemPrompt = '''
你是排课规划助手。规则：1)截止日近、优先级高者先排；2)按计划天数均摊每日；3)同日多课间按强度休息（轻松20-40/中等10-20/压力5-10分钟，课长休息久）；4)贴合偏好时间，备注中已有安排的时间绝不排课；5)只能在时间窗内排课；6)休息可为0。只输出JSON：{"order":[{"courseId":"id","restAfterMinutes":N}],"reason":"一句话"}，order含全部课程各一次。
''';

/// AI 排课客户端：组装 Prompt → 调用 OpenAI 兼容接口 → 解析固定格式。
class AiScheduler {
  AiScheduler({http.Client? client})
      : _client = client ?? _defaultClient();

  final http.Client _client;

  /// 默认客户端：设置 TCP 连接超时，避免 IPv6 地址不可达时连接挂起
  /// （Dart 顺序尝试解析出的地址，IPv6 挂起会导致整体超时；8 秒后自动回退 IPv4）。
  static http.Client _defaultClient() {
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    return IOClient(httpClient);
  }

  /// 请求 AI 排课。
  Future<AiScheduleOutcome> schedule({
    required List<LinkCourse> courses,
    required AiSchedulePrefs prefs,
    required AiScheduleConfig config,
    required String localeCode,
  }) async {
    if (config.apiKey.trim().isEmpty || config.baseUrl.trim().isEmpty) {
      return AiScheduleOutcomeError(
        AiScheduleError(
          type: AiScheduleErrorType.notConfigured,
          message: '尚未配置 AI 排课（请在设置中填写 API Key 与 Base URL）',
        ),
      );
    }
    if (courses.isEmpty) {
      return AiScheduleOutcomeError(
        AiScheduleError(type: AiScheduleErrorType.empty, message: '没有可排课的课程'),
      );
    }

    final uri = Uri.parse(
      '${config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/chat/completions',
    );
    final body = jsonEncode({
      'model': config.model.trim(),
      'temperature': 0.3,
      'messages': [
        {'role': 'system', 'content': aiScheduleSystemPrompt},
        {
          'role': 'user',
          'content': _buildUserPrompt(
            courses: courses,
            prefs: prefs,
            window: config.windowDescription,
            localeCode: localeCode,
          ),
        },
      ],
    });

    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiKey.trim()}',
            },
            body: body,
          )
          .timeout(config.timeout);
    } on TimeoutException {
      return AiScheduleOutcomeError(
        AiScheduleError(
          type: AiScheduleErrorType.network,
          message:
              'AI 请求超时（${config.timeout.inSeconds} 秒）：${config.baseUrl.trim()} 无响应。'
              '请检查设备网络（能否用浏览器打开该地址）；使用 OpenAI 需确保设备可直连 api.openai.com',
        ),
      );
    } on HandshakeException {
      return AiScheduleOutcomeError(
        AiScheduleError(
          type: AiScheduleErrorType.network,
          message:
              'TLS 握手失败（${config.baseUrl.trim()}）。请检查设备系统时间是否正确、'
              '是否开启了 VPN/代理或网络被拦截',
        ),
      );
    } on http.ClientException catch (e) {
      return AiScheduleOutcomeError(
        AiScheduleError(
          type: AiScheduleErrorType.network,
          message:
              '网络连接失败（${config.baseUrl.trim()}）：${e.message}。'
              '请检查网络；若浏览器可访问但 App 不行，可能是网络限制了非浏览器流量',
        ),
      );
    } catch (e) {
      debugPrint('[ai_scheduler] request failed: $e');
      return AiScheduleOutcomeError(
        AiScheduleError(
          type: AiScheduleErrorType.network,
          message: 'AI 请求失败：$e',
        ),
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return AiScheduleOutcomeError(
        AiScheduleError(
          type: AiScheduleErrorType.http,
          message: 'AI 接口返回错误（HTTP ${response.statusCode}）：${_trimBody(response.body)}',
        ),
      );
    }

    final parsed = _parseResponse(response.body);
    if (parsed == null) {
      return AiScheduleOutcomeError(
        AiScheduleError(
          type: AiScheduleErrorType.parse,
          message: 'AI 返回内容无法解析，请重试或更换模型',
        ),
      );
    }
    if (parsed.ordered.isEmpty) {
      return AiScheduleOutcomeError(
        AiScheduleError(type: AiScheduleErrorType.empty, message: 'AI 没有返回任何课程顺序'),
      );
    }
    return AiScheduleOutcomeSuccess(parsed);
  }

  /// 网络诊断：GET 根路径 + 三个尺寸的 POST（300B/1200B/2500B）。
  /// 用于精确定位网络可传输的请求体上限（MTU 黑洞阈值）。
  Future<String> diagnoseConnection(String baseUrl, {String apiKey = ''}) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final getUri = Uri.parse('$base/');
    final postUri = Uri.parse('$base/chat/completions');
    final getResult = await _probe('GET', getUri, apiKey: apiKey, body: null);
    final results = <String>[];
    for (final size in const [300, 1200, 2500]) {
      final body =
          '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"${'a' * size}"}]}';
      final result = await _probe('POST', postUri, apiKey: apiKey, body: body);
      results.add('$size B: $result');
    }
    return 'GET: $getResult\n${results.join('\n')}';
  }

  Future<String> _probe(
    String method,
    Uri uri, {
    required String apiKey,
    required String? body,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final request = http.Request(method, uri);
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = body;
      }
      if (apiKey.trim().isNotEmpty) {
        request.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
      }
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 10));
      final resp = await http.Response.fromStream(streamed);
      stopwatch.stop();
      return 'HTTP ${resp.statusCode}，${stopwatch.elapsedMilliseconds}ms';
    } on TimeoutException {
      stopwatch.stop();
      return '超时（10 秒无响应）';
    } on http.ClientException catch (e) {
      stopwatch.stop();
      return '失败：${e.message}';
    } catch (e) {
      stopwatch.stop();
      return '失败：$e';
    }
  }

  String _buildUserPrompt({
    required List<LinkCourse> courses,
    required AiSchedulePrefs prefs,
    required String window,
    required String localeCode,
  }) {
    final intensityLabel = switch (prefs.intensity) {
      StudyIntensity.relaxed => '轻松',
      StudyIntensity.medium => '中等',
      StudyIntensity.stressed => '压力',
    };
    final timePreference =
        prefs.timePreference.trim().isEmpty ? '全天' : prefs.timePreference.trim();
    final notes = prefs.notes.trim().isEmpty ? '无' : prefs.notes.trim();
    final courseLines = [
      for (final c in courses)
        '${c.id}|${c.title}|${c.durationMinutes}分钟|${c.priority.name}'
            '${c.deadlineDay == null ? '' : '|截止${c.deadlineDay}'}'
            '|${_domainOf(c.url)}',
    ].join(';');
    return [
      '语言:$localeCode 强度:$intensityLabel 天数:${prefs.days} 备注:$notes 偏好:$timePreference 时间窗:$window',
      '课程:$courseLines',
    ].join('\n');
  }

  /// 提取 URL 域名（仅作提示用，避免长链接撑大请求体）。
  static String _domainOf(String url) {
    try {
      final host = Uri.parse(url.trim()).host;
      return host.isEmpty ? '' : host;
    } catch (_) {
      return '';
    }
  }

  /// 解析 AI 响应中的固定格式 JSON。
  AiScheduleSuccess? _parseResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final first = choices.first;
      if (first is! Map) return null;
      final message = first['message'];
      if (message is! Map) return null;
      final content = message['content'];
      if (content is! String || content.trim().isEmpty) return null;
      return _parseContent(content);
    } catch (e) {
      debugPrint('[ai_scheduler] response decode failed: $e');
      return null;
    }
  }

  AiScheduleSuccess? _parseContent(String content) {
    try {
      final trimmed = content.trim().replaceFirst(
        RegExp(r'^```(?:json)?\s*', caseSensitive: false),
        '',
      );
      final cleaned = trimmed.replaceFirst(RegExp(r'\s*```$'), '');
      final decoded = jsonDecode(cleaned);
      final List<dynamic> rawItems;
      String reason = '';
      if (decoded is Map) {
        rawItems = decoded['order'] is List ? decoded['order'] as List : const [];
        reason = decoded['reason'] as String? ?? '';
      } else if (decoded is List) {
        rawItems = decoded;
      } else {
        return null;
      }
      final ordered = <OrderedCourse>[];
      for (final item in rawItems) {
        if (item is! Map) continue;
        final courseId = item['courseId'];
        if (courseId is! String || courseId.trim().isEmpty) continue;
        final restRaw = item['restAfterMinutes'];
        final rest = restRaw is num ? restRaw.toInt() : 0;
        ordered.add((courseId: courseId.trim(), restAfterMinutes: rest < 0 ? 0 : rest));
      }
      // JSON 结构合法但没有任何有效课程 → 返回空列表，由调用方判定 empty。
      return AiScheduleSuccess(ordered: ordered, reason: reason.trim());
    } catch (e) {
      debugPrint('[ai_scheduler] content parse failed: $e');
      return null;
    }
  }

  static String _trimBody(String body) {
    final trimmed = body.trim();
    return trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed;
  }
}

/// AI 排课配置读写：提供商/Base URL/模型 → SharedPreferences；API Key → 加密存储。
class AiScheduleSettings {
  AiScheduleSettings({SecretStore? secretStore})
      : _secretStore = secretStore ?? SecretStore();

  static const _providerKey = 'ai_schedule_provider';
  static const _baseUrlKey = 'ai_schedule_base_url';
  static const _modelKey = 'ai_schedule_model';
  static const _setupPrefsKey = 'ai_schedule_setup_prefs';

  final SecretStore _secretStore;

  Future<AiScheduleConfig> loadConfig({String windowDescription = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final provider = AiProvider.fromName(prefs.getString(_providerKey));
    return AiScheduleConfig(
      provider: provider,
      baseUrl: prefs.getString(_baseUrlKey)?.trim() ?? provider.defaultBaseUrl,
      apiKey: await _secretStore.readAiSchedulerApiKey(),
      model: prefs.getString(_modelKey)?.trim() ?? provider.defaultModel,
      windowDescription: windowDescription,
    );
  }

  Future<void> saveConfig({
    AiProvider? provider,
    String? baseUrl,
    String? model,
    String? apiKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (provider != null) {
      await prefs.setString(_providerKey, provider.name);
    }
    if (baseUrl != null) {
      await prefs.setString(_baseUrlKey, baseUrl.trim());
    }
    if (model != null) {
      await prefs.setString(_modelKey, model.trim());
    }
    if (apiKey != null) {
      await _secretStore.writeAiSchedulerApiKey(apiKey);
    }
  }

  /// 读取上次排课设置（未保存过返回 null）。
  Future<AiSchedulePrefs?> loadSetupPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_setupPrefsKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AiSchedulePrefs.fromJson(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
    } catch (e) {
      debugPrint('[ai_scheduler] setup prefs decode failed: $e');
      return null;
    }
  }

  Future<void> saveSetupPrefs(AiSchedulePrefs prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_setupPrefsKey, jsonEncode(prefs.toJson()));
  }
}
