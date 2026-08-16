import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, HttpClient;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/secret_store.dart';
import 'ai_skill_package.dart';
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
    AiProvider.openai => const ['gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna'],
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

  static StudyIntensity fromName(String? value) => StudyIntensity.values
      .firstWhere((i) => i.name == value, orElse: () => StudyIntensity.medium);
}

/// 排课开始时间：从现在开始（今天剩余时段）或从明天开始。
enum ScheduleStartMode {
  now,
  tomorrow;

  String get name => switch (this) {
    ScheduleStartMode.now => 'now',
    ScheduleStartMode.tomorrow => 'tomorrow',
  };

  static ScheduleStartMode fromName(String? value) => ScheduleStartMode.values
      .firstWhere((m) => m.name == value, orElse: () => ScheduleStartMode.now);
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

  factory AiSchedulePrefs.fromJson(Map<String, dynamic> json) =>
      AiSchedulePrefs(
        intensity: StudyIntensity.fromName(json['intensity'] as String?),
        days: (json['days'] as num?)?.toInt() ?? 7,
        notes: json['notes'] as String? ?? '',
        timePreference: json['timePreference'] as String? ?? '',
        startMode: ScheduleStartMode.fromName(json['startMode'] as String?),
      );
}

/// 从备注文本中解析学习时段与不可用时段（分钟）。
///
/// 支持中文表述，如：
/// - "9点到12点，13点半到晚上9点学习，下午1点到6点有事"
///   → 学习 [9:00-12:00, 13:30-21:00]，不可用 [13:00-18:00]
/// - "周一到周三晚上有课，周四下午开会"（无法可靠解析时返回空）
///
/// 规则：
/// - 提取 "X点/点半 到 Y点/点半"、"X:MM-Y:MM" 形式的时间段；
/// - 时间段后紧跟"学习/学/可用/安排"等词 → 学习时段；
/// - 时间段后紧跟"有事/不可用/不学/没空/开会/有课"等词 → 不可用时段；
/// - 无明确关键词的时间段默认视为学习时段（用户多半在描述可学习时间）。
/// 无法解析出任何时段时返回空列表（调用方回退通用设置）。
({List<(int, int)> learning, List<(int, int)> blocked}) parseNotesTimeRanges(
  String notes,
) {
  final learning = <(int, int)>[];
  final blocked = <(int, int)>[];
  if (notes.trim().isEmpty) return (learning: learning, blocked: blocked);

  // 时间段模式：起始 到 结束。支持 "9点到12点"、"13点半到晚上9点"、"9:00-12:00"、"1点到6点"、"下午1点到6点"。
  // "点半" 用 (半) 捕获；起始/结束的 "下午/晚上/夜间" 等前缀分别用 g2/g5 捕获（小时 ≤ 11 时 +12）。
  final pattern = RegExp(
    r'(凌晨|早上|上午|中午|下午|傍晚|晚上|晚间|夜里|深夜)?'
    r'(\d{1,2})(?:点(半)?|:(\d{2}))?\s*(?:到|至|-|—|~)\s*'
    r'(凌晨|早上|上午|中午|下午|傍晚|晚上|晚间|夜里|深夜)?'
    r'(\d{1,2})(?:点(半)?|:(\d{2}))?',
  );
  for (final m in pattern.allMatches(notes)) {
    final start = _parseTimeToken(
      m.group(2),
      m.group(3),
      m.group(4),
      pmPrefix: m.group(1),
    );
    var end = _parseTimeToken(
      m.group(6),
      m.group(7),
      m.group(8),
      pmPrefix: m.group(5),
    );
    // 结束无前缀但起始带"下午/晚上"语境且结束原始小时为 1-11 → 结束也视为下午（如"下午1点到6点"）。
    if (end != null &&
        start != null &&
        m.group(5) == null &&
        m.group(1) != null &&
        RegExp(r'下午|傍晚|晚上|晚间|夜里|深夜').hasMatch(m.group(1)!) &&
        end > 0 &&
        end < 12 * 60 &&
        end <= start) {
      end += 12 * 60;
    }
    if (start == null || end == null || end <= start) continue;
    // 判断该时段语义：只看紧跟时段结束后的少量字符（避免跨时段误判）。
    // 否定词（不学/不学习/没空/休息/有事等）优先 → 该时段为不可用；
    // 明确学习词（学习/学/可用/安排/用来学）→ 学习时段；无语义词 → 默认学习。
    final after = notes
        .substring(m.end, m.end + 6 > notes.length ? notes.length : m.end + 6)
        .trim();
    final isBlocked = RegExp(r'不学|不学习|有事|不可用|没空|开会|有课|上班|休息|忙').hasMatch(after);
    if (isBlocked) {
      blocked.add((start, end));
    } else {
      // 无语义关键词：默认视为学习时段（用户多半在描述可学习时间）。
      learning.add((start, end));
    }
  }
  // 去重并排序。
  final dedupLearning = <(int, int)>[];
  for (final r in learning) {
    if (!dedupLearning.any((x) => x.$1 == r.$1 && x.$2 == r.$2)) {
      dedupLearning.add(r);
    }
  }
  dedupLearning.sort((a, b) => a.$1.compareTo(b.$1));
  final dedupBlocked = <(int, int)>[];
  for (final r in blocked) {
    if (!dedupBlocked.any((x) => x.$1 == r.$1 && x.$2 == r.$2)) {
      dedupBlocked.add(r);
    }
  }
  dedupBlocked.sort((a, b) => a.$1.compareTo(b.$1));
  return (learning: dedupLearning, blocked: dedupBlocked);
}

/// 解析时间 token → 分钟；失败返回 null。
/// [halfRaw] 为 "半"（半点 = 30 分钟）；[minuteRaw] 为 "HH:MM" 的分钟部分。
/// [pmPrefix] 为 "下午/傍晚/晚上/晚间/夜里/深夜" 等前缀：小时 ≤ 11 时 +12 小时；
/// "中午" 保持 12；"凌晨/早上/上午" 不调整。
int? _parseTimeToken(
  String? hourRaw,
  String? halfRaw,
  String? minuteRaw, {
  String? pmPrefix,
}) {
  if (hourRaw == null) return null;
  var hour = int.tryParse(hourRaw);
  if (hour == null || hour < 0 || hour > 23) return null;
  final pm =
      pmPrefix != null && RegExp(r'下午|傍晚|晚上|晚间|夜里|深夜').hasMatch(pmPrefix);
  final noon = pmPrefix == '中午';
  if (pm && hour < 12) hour += 12;
  if (noon && hour == 0) hour = 12;
  final minute = halfRaw != null
      ? 30
      : (minuteRaw == null ? 0 : int.tryParse(minuteRaw) ?? 0);
  if (minute < 0 || minute > 59) return null;
  return hour * 60 + minute;
}

/// AI 排课结果（成功：顺序 + 休息 + 每门课颜色 + 思路说明 + 可选的具体时间安排）。
class AiScheduleSuccess {
  const AiScheduleSuccess({
    required this.ordered,
    required this.reason,
    this.colors = const {},
    this.placements = const [],
  });

  final List<OrderedCourse> ordered;
  final String reason;

  /// 每门课的建议颜色（courseId → ARGB 颜色值，来自 AI 输出的 #RRGGBB）。
  final Map<String, int> colors;

  /// AI 给出的具体时间安排（来自新技能文件包输出契约）；为空时由本地引擎自行落位。
  final List<AiPlacement> placements;
}

/// AI 排课失败类型。
enum AiScheduleErrorType { notConfigured, network, http, parse, empty }

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
你是排课规划助手。规则：1)截止日近、优先级高者先排；2)按计划天数均摊每日；3)同日多课间按强度休息（轻松20-40/中等10-20/压力5-10分钟，课长休息久）；4)贴合偏好时间，备注中已有安排的时间绝不排课；5)只能在时间窗内排课；6)休息可为0。每门课给一个与其他课程不同的颜色（#RRGGBB，如#4D6BFE），相邻课程避免同色。只输出JSON：{"order":[{"courseId":"id","restAfterMinutes":N,"color":"#RRGGBB"}],"reason":"一句话"}，order含全部课程各一次。
''';

/// AI 排课客户端：组装 Prompt → 调用 OpenAI 兼容接口 → 解析固定格式。
class AiScheduler {
  AiScheduler({http.Client? client}) : _client = client ?? _defaultClient();

  final http.Client _client;

  /// 默认客户端：设置 TCP 连接超时，避免 IPv6 地址不可达时连接挂起
  /// （Dart 顺序尝试解析出的地址，IPv6 挂起会导致整体超时；8 秒后自动回退 IPv4）。
  static http.Client _defaultClient() {
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    return IOClient(httpClient);
  }

  /// 请求 AI 排课。
  ///
  /// [onToken] 非空时启用流式输出（SSE），AI 生成的文本逐块回调（思考过程实时可见）。
  /// [onUsage] 请求完成后回调 token 用量（prompt/completion），用于用量统计。
  /// [skillPackage] 可选：排课技能文件包（md 提示词 + 算法 JSON）。提供时消息改为
  /// 三段式（system=技能系统提示词 / user=技能文件内容 / user=填充后的排课请求）；
  /// 不提供时回退内置精简 prompt（降级路径）。
  /// [onMessages] 请求发送前回调实际构建的完整消息（用于面板展示"发给 AI 的提示词"）。
  Future<AiScheduleOutcome> schedule({
    required List<LinkCourse> courses,
    required AiSchedulePrefs prefs,
    required AiScheduleConfig config,
    required String localeCode,
    AiSkillPackage? skillPackage,
    void Function(String delta)? onToken,
    void Function(int promptTokens, int completionTokens)? onUsage,
    void Function(List<Map<String, String>> messages)? onMessages,
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
    final messages = _buildMessages(
      courses: courses,
      prefs: prefs,
      config: config,
      localeCode: localeCode,
      skillPackage: skillPackage,
    );
    onMessages?.call(messages);
    final request = http.Request('POST', uri)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.apiKey.trim()}',
      })
      ..body = jsonEncode({
        'model': config.model.trim(),
        'temperature': 0.3,
        if (onToken != null) 'stream': true,
        'messages': messages,
      });

    final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(config.timeout);
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

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final body = await streamed.stream.bytesToString();
      return AiScheduleOutcomeError(
        AiScheduleError(
          type: AiScheduleErrorType.http,
          message: 'AI 接口返回错误（HTTP ${streamed.statusCode}）：${_trimBody(body)}',
        ),
      );
    }

    if (onToken != null) {
      // 流式：逐块回调 AI 输出，最后按累积内容解析结果。
      final String content;
      var promptTokens = 0;
      var completionTokens = 0;
      try {
        final consumed = await _consumeStream(
          streamed,
          config.timeout,
          onToken,
        );
        if (consumed == null) {
          return AiScheduleOutcomeError(
            AiScheduleError(
              type: AiScheduleErrorType.network,
              message: 'AI 流式响应中断（${config.baseUrl.trim()}），请重试',
            ),
          );
        }
        content = consumed.content;
        promptTokens = consumed.promptTokens;
        completionTokens = consumed.completionTokens;
      } on TimeoutException {
        return AiScheduleOutcomeError(
          AiScheduleError(
            type: AiScheduleErrorType.network,
            message:
                'AI 响应超时（${config.timeout.inSeconds} 秒）：${config.baseUrl.trim()}',
          ),
        );
      } catch (e) {
        debugPrint('[ai_scheduler] stream failed: $e');
        return AiScheduleOutcomeError(
          AiScheduleError(
            type: AiScheduleErrorType.network,
            message: 'AI 流式响应失败：$e',
          ),
        );
      }
      onUsage?.call(promptTokens, completionTokens);
      final parsed = _parseContent(content);
      if (parsed == null || parsed.ordered.isEmpty) {
        return AiScheduleOutcomeError(
          AiScheduleError(
            type: AiScheduleErrorType.parse,
            message: 'AI 返回内容无法解析，请重试或更换模型',
          ),
        );
      }
      return AiScheduleOutcomeSuccess(parsed);
    }

    final response = await http.Response.fromStream(streamed);
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
        AiScheduleError(
          type: AiScheduleErrorType.empty,
          message: 'AI 没有返回任何课程顺序',
        ),
      );
    }
    final usage = _extractUsage(response.body);
    onUsage?.call(usage.$1, usage.$2);
    return AiScheduleOutcomeSuccess(parsed);
  }

  /// 读取 SSE 流式响应，逐块回调增量内容，返回累积内容与 usage。
  Future<({String content, int promptTokens, int completionTokens})?>
  _consumeStream(
    http.StreamedResponse resp,
    Duration timeout,
    void Function(String delta) onToken,
  ) async {
    final buffer = StringBuffer();
    var promptTokens = 0;
    var completionTokens = 0;
    try {
      await for (final line
          in resp.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(timeout)) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        final data = trimmed.substring(5).trim();
        if (data == '[DONE]') break;
        if (!data.startsWith('{')) continue;
        try {
          final obj = jsonDecode(data);
          final choices = obj['choices'];
          if (choices is List && choices.isNotEmpty) {
            final delta = choices.first['delta'];
            if (delta is Map) {
              // 推理过程（如 deepseek 的 reasoning_content）：仅实时展示，
              // 不写入 content，避免影响最终 JSON 解析。
              final reasoning =
                  delta['reasoning_content'] ?? delta['reasoning'];
              if (reasoning is String && reasoning.isNotEmpty) {
                onToken(reasoning);
              }
              final content = delta['content'];
              if (content is String && content.isNotEmpty) {
                buffer.write(content);
                onToken(content);
              }
            }
          }
          final usage = obj['usage'];
          if (usage is Map) {
            promptTokens = (usage['prompt_tokens'] as num?)?.toInt() ?? 0;
            completionTokens =
                (usage['completion_tokens'] as num?)?.toInt() ?? 0;
          }
        } catch (_) {}
      }
      return (
        content: buffer.toString(),
        promptTokens: promptTokens,
        completionTokens: completionTokens,
      );
    } catch (e) {
      debugPrint('[ai_scheduler] stream read failed: $e');
      return null;
    }
  }

  /// 从响应体提取 usage（prompt/completion tokens），失败返回 (0, 0)。
  (int, int) _extractUsage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return (0, 0);
      final usage = decoded['usage'];
      if (usage is! Map) return (0, 0);
      final prompt = (usage['prompt_tokens'] as num?)?.toInt() ?? 0;
      final completion = (usage['completion_tokens'] as num?)?.toInt() ?? 0;
      return (prompt, completion);
    } catch (_) {
      return (0, 0);
    }
  }

  /// 网络诊断：GET 根路径 + 三个尺寸的 POST（300B/1200B/2500B）。
  /// 用于精确定位网络可传输的请求体上限（MTU 黑洞阈值）。
  Future<String> diagnoseConnection(
    String baseUrl, {
    String apiKey = '',
  }) async {
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

  /// 组装发给 AI 的 messages：
  /// - 提供 [skillPackage]：三段式（system=技能系统提示词；user=技能文件内容；user=填充后的排课请求）；
  /// - 未提供：回退内置精简 prompt（system + user 两段）。
  List<Map<String, String>> _buildMessages({
    required List<LinkCourse> courses,
    required AiSchedulePrefs prefs,
    required AiScheduleConfig config,
    required String localeCode,
    AiSkillPackage? skillPackage,
  }) {
    if (skillPackage != null) {
      final schemeContent = [
        for (final e in skillPackage.schemeFiles.entries)
          '### ${e.key}\n${e.value}',
      ].join('\n\n');
      return [
        {'role': 'system', 'content': skillPackage.systemPrompt},
        {
          'role': 'user',
          'content': '以下是本次排课需要使用的算法方案文件,请先读取再执行:\n\n$schemeContent',
        },
        {
          'role': 'user',
          'content': _fillUserTemplate(
            template: skillPackage.userTemplate,
            courses: courses,
            prefs: prefs,
            window: config.windowDescription,
            localeCode: localeCode,
          ),
        },
      ];
    }
    return [
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
    ];
  }

  /// 用本次排课数据填充 [user_prompt.md] 模板的 `{{占位符}}`。
  /// 占位符：{{course_count}} {{course_rows}} {{intensity_label}} {{intensity_key}}
  /// {{start_label}} {{days}} {{window_description}} {{fixed_breaks}} {{one_off_blocks}} {{notes}}
  String _fillUserTemplate({
    required String template,
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
    final intensityKey = switch (prefs.intensity) {
      StudyIntensity.relaxed => 'light',
      StudyIntensity.medium => 'medium',
      StudyIntensity.stressed => 'high',
    };
    final startLabel = prefs.startMode == ScheduleStartMode.now ? '现在' : '明天';
    final rows = [
      for (final c in courses)
        '| ${c.id} | ${c.title} | ${c.durationMinutes} |',
    ].join('\n');
    // 从时间窗描述推导固定休息段（如 "08:00-12:00 与 13:00-23:00" → "12:00-13:00"）。
    final fixedBreaks = _fixedBreakFromWindow(window);
    return template
        .replaceAll('{{course_count}}', '${courses.length}')
        .replaceAll('{{course_rows}}', rows)
        .replaceAll('{{intensity_label}}', intensityLabel)
        .replaceAll('{{intensity_key}}', intensityKey)
        .replaceAll('{{start_label}}', startLabel)
        .replaceAll('{{days}}', '${prefs.days}')
        .replaceAll('{{window_description}}', window)
        .replaceAll('{{fixed_breaks}}', fixedBreaks)
        .replaceAll(
          '{{time_preference}}',
          prefs.timePreference.trim().isEmpty
              ? '无'
              : prefs.timePreference.trim(),
        )
        .replaceAll(
          '{{one_off_blocks}}',
          prefs.notes.trim().isEmpty ? '无' : prefs.notes.trim(),
        )
        .replaceAll(
          '{{notes}}',
          prefs.notes.trim().isEmpty ? '无' : prefs.notes.trim(),
        );
  }

  /// 从时间窗描述提取相邻时段之间的休息段；无法解析时返回"无"。
  static String _fixedBreakFromWindow(String window) {
    final parts = window
        .split(RegExp(r'\s*与\s*|\s*,\s*|\s*;\s*'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (parts.length < 2) return '无';
    final ranges = <(int, int)>[];
    for (final p in parts) {
      final m = RegExp(r'(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})').firstMatch(p);
      if (m == null) return '无';
      ranges.add((
        int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!),
        int.parse(m.group(3)!) * 60 + int.parse(m.group(4)!),
      ));
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final breaks = <String>[];
    for (var i = 1; i < ranges.length; i++) {
      if (ranges[i].$1 > ranges[i - 1].$2) {
        breaks.add('${_hhmm(ranges[i - 1].$2)}-${_hhmm(ranges[i].$1)}');
      }
    }
    return breaks.isEmpty ? '无' : breaks.join(' 与 ');
  }

  static String _hhmm(int minute) {
    final h = (minute ~/ 60).toString().padLeft(2, '0');
    final m = (minute % 60).toString().padLeft(2, '0');
    return '$h:$m';
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
    final timePreference = prefs.timePreference.trim().isEmpty
        ? '全天'
        : prefs.timePreference.trim();
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
        rawItems = decoded['order'] is List
            ? decoded['order'] as List
            : const [];
        reason = decoded['reason'] as String? ?? '';
      } else if (decoded is List) {
        rawItems = decoded;
      } else {
        return null;
      }
      final ordered = <OrderedCourse>[];
      final colors = <String, int>{};
      final placements = <AiPlacement>[];
      for (final item in rawItems) {
        if (item is! Map) continue;
        final courseId = item['courseId'];
        if (courseId is! String || courseId.trim().isEmpty) continue;
        final restRaw = item['restAfterMinutes'];
        final rest = restRaw is num ? restRaw.toInt() : 0;
        ordered.add((
          courseId: courseId.trim(),
          restAfterMinutes: rest < 0 ? 0 : rest,
        ));
        final color = _parseColor(item['color']);
        if (color != null) {
          colors[courseId.trim()] = color;
        }
        // 技能文件包输出契约：可含 startDay(1=起始日)/startTime/endTime。
        final placement = _parsePlacement(item);
        if (placement != null) {
          placements.add(placement);
        }
      }
      // JSON 结构合法但没有任何有效课程 → 返回空列表，由调用方判定 empty。
      return AiScheduleSuccess(
        ordered: ordered,
        reason: reason.trim(),
        colors: colors,
        placements: placements,
      );
    } catch (e) {
      debugPrint('[ai_scheduler] content parse failed: $e');
      return null;
    }
  }

  /// 解析单条 AI 输出的具体时间（startDay/startTime/endTime）；缺任一字段返回 null。
  AiPlacement? _parsePlacement(Map<dynamic, dynamic> item) {
    final courseId = item['courseId'];
    if (courseId is! String || courseId.trim().isEmpty) return null;
    final startDayRaw = item['startDay'];
    final startTime = item['startTime'];
    final endTime = item['endTime'];
    if (startDayRaw is! num || startTime is! String || endTime is! String) {
      return null;
    }
    final start = _parseHhMm(startTime);
    final end = _parseHhMm(endTime);
    if (start == null || end == null || end <= start) return null;
    final dayOffset = startDayRaw.toInt() - 1;
    if (dayOffset < 0) return null;
    return AiPlacement(
      courseId: courseId.trim(),
      dayOffset: dayOffset,
      startMinute: start,
      endMinute: end,
    );
  }

  /// 解析 "HH:MM" → 分钟；失败返回 null。
  static int? _parseHhMm(String value) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (m == null) return null;
    final hour = int.tryParse(m.group(1)!);
    final minute = int.tryParse(m.group(2)!);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  /// 解析颜色：#RRGGBB / #AARRGGBB → ARGB int；数字直接取整；失败返回 null。
  static int? _parseColor(Object? raw) {
    if (raw is num) return raw.toInt();
    if (raw is! String) return null;
    var hex = raw.trim().replaceFirst('#', '');
    if (hex.length == 6) {
      final v = int.tryParse(hex, radix: 16);
      return v == null ? null : (0xFF000000 | v);
    }
    if (hex.length == 8) {
      return int.tryParse(hex, radix: 16);
    }
    return null;
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

/// 单个模型的用量统计。
class AiModelUsage {
  const AiModelUsage({
    required this.provider,
    required this.model,
    required this.requests,
    required this.promptTokens,
    required this.completionTokens,
  });

  final String provider;
  final String model;
  final int requests;
  final int promptTokens;
  final int completionTokens;

  int get totalTokens => promptTokens + completionTokens;
}

/// 模型价格（美元/百万 token），用于估算花费（仅作参考）。
double _inputPricePerMillion(String model) => switch (model) {
  'deepseek-v4-flash' => 0.1,
  'deepseek-v4-pro' => 0.5,
  'gpt-5.6-luna' => 0.4,
  'gpt-5.6-terra' => 1.0,
  'gpt-5.6-sol' => 2.5,
  _ => 1.0,
};

double _outputPricePerMillion(String model) => switch (model) {
  'deepseek-v4-flash' => 0.4,
  'deepseek-v4-pro' => 2.0,
  'gpt-5.6-luna' => 1.6,
  'gpt-5.6-terra' => 4.0,
  'gpt-5.6-sol' => 10.0,
  _ => 4.0,
};

/// 估算一次用量的花费（美元）。
double estimateCostInUsd(AiModelUsage usage) {
  return usage.promptTokens / 1e6 * _inputPricePerMillion(usage.model) +
      usage.completionTokens / 1e6 * _outputPricePerMillion(usage.model);
}

/// AI 用量统计：按模型累计 token 与请求次数，本地持久化。
/// 供设置页展示"已用 token / 花费"，帮助小白用户了解用量。
class AiUsageStats {
  AiUsageStats._();

  static final AiUsageStats instance = AiUsageStats._();

  static const _key = 'ai_usage_stats';

  bool _loaded = false;
  final Map<String, Map<String, dynamic>> _stats = {};

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            final v = e.value;
            if (v is Map) {
              _stats[e.key.toString()] = v.map(
                (k, vv) => MapEntry(k.toString(), vv),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('[ai_scheduler] usage stats decode failed: $e');
      }
    }
    _loaded = true;
  }

  /// 记录一次请求的 token 用量。
  Future<void> record({
    required AiProvider provider,
    required String model,
    required int promptTokens,
    required int completionTokens,
  }) async {
    await ensureLoaded();
    final entry = _stats[model] ?? <String, dynamic>{};
    entry['provider'] = provider.name;
    entry['requests'] = ((entry['requests'] as num?)?.toInt() ?? 0) + 1;
    entry['promptTokens'] =
        ((entry['promptTokens'] as num?)?.toInt() ?? 0) + promptTokens;
    entry['completionTokens'] =
        ((entry['completionTokens'] as num?)?.toInt() ?? 0) + completionTokens;
    _stats[model] = entry;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_stats));
  }

  /// 各模型用量（按 token 总量降序）。
  List<AiModelUsage> get entries {
    final result = [
      for (final e in _stats.entries)
        AiModelUsage(
          provider: e.value['provider'] as String? ?? '',
          model: e.key,
          requests: (e.value['requests'] as num?)?.toInt() ?? 0,
          promptTokens: (e.value['promptTokens'] as num?)?.toInt() ?? 0,
          completionTokens: (e.value['completionTokens'] as num?)?.toInt() ?? 0,
        ),
    ]..sort((a, b) => b.totalTokens.compareTo(a.totalTokens));
    return result;
  }

  int get totalRequests => entries.fold(0, (sum, e) => sum + e.requests);

  int get totalTokens => entries.fold(0, (sum, e) => sum + e.totalTokens);

  double get totalCostUsd =>
      entries.fold(0.0, (sum, e) => sum + estimateCostInUsd(e));

  /// 仅测试用：清空统计。
  @visibleForTesting
  Future<void> debugReset() async {
    _stats.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
