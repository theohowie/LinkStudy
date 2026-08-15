import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
    this.timeout = const Duration(seconds: 30),
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

/// 本次排课设置（记住上次选择）。
class AiSchedulePrefs {
  const AiSchedulePrefs({
    this.intensity = StudyIntensity.medium,
    this.days = 7,
    this.notes = '',
    this.timePreference = '',
  });

  final StudyIntensity intensity;
  final int days; // 计划几天学完
  final String notes; // 备注：这段时间哪些时间已有安排
  final String timePreference; // 倾向的学习时间段；空 = 全天

  Map<String, dynamic> toJson() => {
        'intensity': intensity.name,
        'days': days,
        'notes': notes,
        'timePreference': timePreference,
      };

  factory AiSchedulePrefs.fromJson(Map<String, dynamic> json) => AiSchedulePrefs(
        intensity: StudyIntensity.fromName(json['intensity'] as String?),
        days: (json['days'] as num?)?.toInt() ?? 7,
        notes: json['notes'] as String? ?? '',
        timePreference: json['timePreference'] as String? ?? '',
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
const aiScheduleSystemPrompt = '''
你是专业的课程时间规划助手，负责为用户安排网课学习计划。

排课原则：
1. 截止日期近的课程优先安排；截止日期相同则优先级高（high > medium > low）优先。
2. 在用户给定的计划天数内，把课程均匀分配到每天，避免单日负担过重。
3. 同一天安排多门课程时，在课程之间安排休息时间：学习强度越轻松休息越长（轻松约 20-40 分钟、中等约 10-20 分钟、压力约 5-10 分钟），同时参考课程时长（课程越长休息越久）。
4. 尽量贴合用户偏好的学习时间段；如果用户备注了某些时间段已有安排，绝不能把课程安排到那些时间。
5. 每天的学习只能安排在用户给定的时间窗内（开始 ~ 午休开始、午休结束 ~ 结束；午休时间不能排课）。
6. 每门课程时长固定（分钟）；休息时间是建议值，可以设为 0。

输出必须是严格的 JSON，不要输出任何其他文字、解释或 markdown：
{"order":[{"courseId":"课程id","restAfterMinutes":休息分钟数}],"reason":"用一两句话说明排课思路"}
其中 order 数组的顺序就是学习顺序，必须包含输入的全部课程且每门只出现一次。
''';

/// AI 排课客户端：组装 Prompt → 调用 OpenAI 兼容接口 → 解析固定格式。
class AiScheduler {
  AiScheduler({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

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
    } on http.ClientException {
      return AiScheduleOutcomeError(
        AiScheduleError(
          type: AiScheduleErrorType.network,
          message: '网络连接失败（${config.baseUrl.trim()}），请检查网络后重试',
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

  String _buildUserPrompt({
    required List<LinkCourse> courses,
    required AiSchedulePrefs prefs,
    required String window,
    required String localeCode,
  }) {
    final intensityLabel = switch (prefs.intensity) {
      StudyIntensity.relaxed => '轻松（休息长一点，节奏舒缓）',
      StudyIntensity.medium => '中等（正常节奏）',
      StudyIntensity.stressed => '压力（紧凑高效，休息短）',
    };
    final timePreference =
        prefs.timePreference.trim().isEmpty ? '全天（无特别偏好）' : prefs.timePreference.trim();
    final notes = prefs.notes.trim().isEmpty
        ? '无'
        : prefs.notes.trim();
    final courseLines = [
      for (final c in courses)
        '- id: ${c.id}, 名称: ${c.title}, 时长: ${c.durationMinutes}分钟'
            ', 截止: ${c.deadlineDay == null ? '无' : '${c.deadlineDay!}（epochDay）'}'
            ', 优先级: ${c.priority.name}, 链接: ${c.url.isEmpty ? '无' : c.url}',
    ].join('\n');
    return [
      '当前语言：$localeCode',
      '学习强度：$intensityLabel',
      '计划天数：${prefs.days} 天（从今天起 ${prefs.days} 天内安排）',
      '用户备注（这些时间已有安排，不能排课）：$notes',
      '时间偏好：$timePreference',
      '每天可用时间窗（本地强制约束）：$window',
      '课程清单：',
      courseLines,
    ].join('\n');
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
