import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linkstudy/courses/ai_scheduler.dart';
import 'package:linkstudy/courses/ai_skill_package.dart';
import 'package:linkstudy/courses/link_course.dart';
import 'package:linkstudy/services/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.sse);

  final String sse;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      http.ByteStream.fromBytes(utf8.encode(sse)),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}

class _FakeSecretStore implements SecretStore {
  String aiKey = '';

  @override
  Future<String> readAiSchedulerApiKey() async => aiKey;

  @override
  Future<void> writeAiSchedulerApiKey(String value) async {
    aiKey = value;
  }

  @override
  Future<String> readCustomSchoolImportApiKey() async => '';

  @override
  Future<void> writeCustomSchoolImportApiKey(String value) async {}
}

LinkCourse _course(String id, {int duration = 40}) => LinkCourse(
  id: id,
  url: 'https://example.com/$id',
  title: '课程$id',
  durationMinutes: duration,
  createdAt: DateTime(2026, 1, 5),
);

AiScheduleConfig _config({
  String apiKey = 'sk-test',
  String windowDescription = '08:00-12:00 与 13:00-23:00',
}) => AiScheduleConfig(
  provider: AiProvider.deepseek,
  baseUrl: 'https://api.deepseek.com/v1',
  apiKey: apiKey,
  model: 'deepseek-chat',
  windowDescription: windowDescription,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const prefs = AiSchedulePrefs(
    intensity: StudyIntensity.medium,
    days: 3,
    notes: '周一下午有课',
    timePreference: '晚上 19:00-22:00',
  );

  group('AiScheduler.schedule', () {
    test('成功：标准格式解析出顺序与休息', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      '{"order":[{"courseId":"a","restAfterMinutes":15},'
                      '{"courseId":"b","restAfterMinutes":0}],'
                      '"reason":"截止日期优先"}',
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final outcome = await AiScheduler(client: client).schedule(
        courses: [_course('a'), _course('b')],
        prefs: prefs,
        config: _config(),
        localeCode: 'zh-CN',
      );
      final success = outcome as AiScheduleOutcomeSuccess;
      expect(success.value.ordered, hasLength(2));
      expect(success.value.ordered[0].courseId, 'a');
      expect(success.value.ordered[0].restAfterMinutes, 15);
      expect(success.value.ordered[1].restAfterMinutes, 0);
      expect(success.value.reason, '截止日期优先');
    });

    test('解析课程颜色（#RRGGBB → ARGB）', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      '{"order":[{"courseId":"a","restAfterMinutes":5,'
                      '"color":"#4D6BFE"},{"courseId":"b","restAfterMinutes":0}],'
                      '"reason":"x"}',
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final outcome = await AiScheduler(client: client).schedule(
        courses: [_course('a'), _course('b')],
        prefs: prefs,
        config: _config(),
        localeCode: 'zh-CN',
      );
      final success = outcome as AiScheduleOutcomeSuccess;
      expect(success.value.colors['a'], 0xFF4D6BFE);
      // 未提供颜色的课程不在映射中。
      expect(success.value.colors.containsKey('b'), isFalse);
    });

    test('容错：markdown 代码块包裹与裸数组', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '```json\n[{"courseId":"a"}]\n```'},
              },
            ],
          }),
          200,
        );
      });
      final outcome = await AiScheduler(client: client).schedule(
        courses: [_course('a')],
        prefs: prefs,
        config: _config(),
        localeCode: 'zh-CN',
      );
      final success = outcome as AiScheduleOutcomeSuccess;
      expect(success.value.ordered.single.courseId, 'a');
      expect(success.value.ordered.single.restAfterMinutes, 0);
    });

    test('请求包含内置排课 Skill 与课程/设置数据', () async {
      String? capturedBody;
      final client = MockClient((request) async {
        capturedBody = request.body;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      '{"order":[{"courseId":"a","restAfterMinutes":10}],"reason":"x"}',
                },
              },
            ],
          }),
          200,
        );
      });
      await AiScheduler(client: client).schedule(
        courses: [_course('a', duration: 60), _course('b')],
        prefs: prefs,
        config: _config(),
        localeCode: 'zh-CN',
      );
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      final system = messages[0]['content'] as String;
      final user = messages[1]['content'] as String;
      expect(system, contains('排课规划助手'));
      expect(system, contains('restAfterMinutes'));
      expect(user, contains('课程a'));
      expect(user, contains('60分钟'));
      expect(user, contains('中等'));
      expect(user, contains('天数:3'));
      expect(user, contains('周一下午有课'));
      expect(user, contains('晚上 19:00-22:00'));
      expect(user, contains('08:00-12:00'));
      expect(body['model'], 'deepseek-chat');
    });

    test('技能包模式：三段式消息（system + 技能文件 + 填充后的请求）', () async {
      String? capturedBody;
      final client = MockClient((request) async {
        capturedBody = request.body;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      '{"order":[{"courseId":"a","restAfterMinutes":10}],"reason":"x"}',
                },
              },
            ],
          }),
          200,
        );
      });
      final skillPackage = AiSkillPackage(
        systemPrompt: '# 排课技能系统提示词\n请读取技能文件执行。',
        userTemplate: [
          '请使用软件技能为这 {{course_count}} 节课进行排序,注意用户的要求设置。',
          '## 课程清单',
          '{{course_rows}}',
          '## 用户要求设置',
          '- **学习强度**:{{intensity_label}}({{intensity_key}})',
          '- **排课窗口**:从{{start_label}}开始,共 {{days}} 天',
          '- **每日可用时间窗**:{{window_description}}',
          '- **每日固定休息段**:{{fixed_breaks}}',
          '- **单次不可用时段**:{{one_off_blocks}}',
          '- **备注**:{{notes}}',
        ].join('\n'),
        schemeFiles: {
          'ahp_priority_algorithm.json': '{"algorithm":"ahp"}',
          'output_format.json': '{"schema":"order"}',
        },
      );
      await AiScheduler(client: client).schedule(
        courses: [_course('a', duration: 60)],
        prefs: const AiSchedulePrefs(
          intensity: StudyIntensity.medium,
          days: 3,
          notes: '周一下午有课',
        ),
        config: _config(),
        localeCode: 'zh-CN',
        skillPackage: skillPackage,
      );
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(3), reason: '技能包模式应为三段式消息');

      final system = messages[0]['content'] as String;
      expect(system, contains('请读取技能文件执行'));

      final scheme = messages[1]['content'] as String;
      expect(scheme, contains('ahp_priority_algorithm.json'));
      expect(scheme, contains('{"algorithm":"ahp"}'));
      expect(scheme, contains('output_format.json'));

      final user = messages[2]['content'] as String;
      expect(user, contains('请使用软件技能为这 1 节课进行排序'));
      expect(user, contains('| a | 课程a | 60 |'));
      expect(user, contains('中等'));
      expect(user, contains('medium'));
      expect(user, contains('从现在开始'));
      expect(user, contains('共 3 天'));
      expect(user, contains('08:00-12:00 与 13:00-23:00'));
      // 时间窗两段之间的休息段被推导为固定休息段。
      expect(user, contains('12:00-13:00'));
      expect(user, contains('周一下午有课'));
    });

    test('技能包模式：固定休息段从时间窗推导，单段时间窗为无', () async {
      String? capturedBody;
      final client = MockClient((request) async {
        capturedBody = request.body;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      '{"order":[{"courseId":"a","restAfterMinutes":0}],"reason":"x"}',
                },
              },
            ],
          }),
          200,
        );
      });
      const skillPackage = AiSkillPackage(
        systemPrompt: 'sys',
        userTemplate: '{{fixed_breaks}}|{{notes}}',
        schemeFiles: {},
      );
      await AiScheduler(client: client).schedule(
        courses: [_course('a')],
        prefs: const AiSchedulePrefs(),
        config: _config(windowDescription: '09:00-18:00'),
        localeCode: 'zh-CN',
        skillPackage: skillPackage,
      );
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      final user = (body['messages'] as List<dynamic>)[2]['content'] as String;
      expect(user, '无|无');
    });

    test('请求体保持精简（MTU 黑洞环境下大请求会被丢）', () async {
      String? capturedBody;
      final client = MockClient((request) async {
        capturedBody = request.body;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      '{"order":[{"courseId":"a","restAfterMinutes":10}],"reason":"x"}',
                },
              },
            ],
          }),
          200,
        );
      });
      final courses = [
        for (var i = 0; i < 5; i++) _course('course_$i', duration: 40 + i * 10),
      ];
      await AiScheduler(client: client).schedule(
        courses: courses,
        prefs: const AiSchedulePrefs(
          intensity: StudyIntensity.stressed,
          days: 5,
          notes: '周一二有安排，周三晚上有会',
          timePreference: '晚上 19:00-22:00',
        ),
        config: _config(),
        localeCode: 'zh-CN',
      );
      final bytes = utf8.encode(capturedBody!).length;
      // 5 门课程 + 完整设置的请求体应远小于 MTU 分片阈值（1500），保证单包可达。
      expect(bytes, lessThan(1500), reason: '请求体 $bytes 字节过大，MTU 黑洞下会被丢弃');
    });

    test('流式输出：onToken 逐块回调并正确解析结果', () async {
      final sse = [
        'data: {"choices":[{"delta":{"content":"{\\"order\\":"}}]}',
        'data: {"choices":[{"delta":{"content":"[{\\"courseId\\":\\"a\\"}]}"}}]}',
        'data: [DONE]',
      ].join('\n');
      final tokens = <String>[];
      final outcome = await AiScheduler(client: _StreamingClient(sse)).schedule(
        courses: [_course('a')],
        prefs: prefs,
        config: _config(),
        localeCode: 'zh-CN',
        onToken: tokens.add,
      );
      final success = outcome as AiScheduleOutcomeSuccess;
      expect(success.value.ordered.single.courseId, 'a');
      expect(tokens, isNotEmpty);
      expect(tokens.join(), contains('courseId'));
    });

    test('usage 回调返回 prompt/completion tokens', () async {
      int? prompt;
      int? completion;
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      '{"order":[{"courseId":"a","restAfterMinutes":0}],"reason":"x"}',
                },
              },
            ],
            'usage': {'prompt_tokens': 123, 'completion_tokens': 45},
          }),
          200,
        );
      });
      final outcome = await AiScheduler(client: client).schedule(
        courses: [_course('a')],
        prefs: prefs,
        config: _config(),
        localeCode: 'zh-CN',
        onUsage: (p, c) {
          prompt = p;
          completion = c;
        },
      );
      expect(outcome, isA<AiScheduleOutcomeSuccess>());
      expect(prompt, 123);
      expect(completion, 45);
    });

    test('未配置 API Key 返回 notConfigured（不发请求）', () async {
      var requested = false;
      final client = MockClient((request) async {
        requested = true;
        return http.Response('{}', 200);
      });
      final outcome = await AiScheduler(client: client).schedule(
        courses: [_course('a')],
        prefs: prefs,
        config: _config(apiKey: ''),
        localeCode: 'zh-CN',
      );
      expect(requested, isFalse);
      final error = outcome as AiScheduleOutcomeError;
      expect(error.error.type, AiScheduleErrorType.notConfigured);
    });

    test('HTTP 非 2xx 返回 http 错误', () async {
      final client = MockClient((request) async {
        return http.Response('bad key', 401);
      });
      final outcome = await AiScheduler(client: client).schedule(
        courses: [_course('a')],
        prefs: prefs,
        config: _config(),
        localeCode: 'zh-CN',
      );
      final error = outcome as AiScheduleOutcomeError;
      expect(error.error.type, AiScheduleErrorType.http);
      expect(error.error.message, contains('401'));
    });

    test('网络异常返回 network 错误', () async {
      final client = MockClient((request) async {
        throw http.ClientException('connection refused');
      });
      final outcome = await AiScheduler(client: client).schedule(
        courses: [_course('a')],
        prefs: prefs,
        config: _config(),
        localeCode: 'zh-CN',
      );
      final error = outcome as AiScheduleOutcomeError;
      expect(error.error.type, AiScheduleErrorType.network);
    });

    test('响应内容无法解析返回 parse 错误', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '我不是 JSON'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final outcome = await AiScheduler(client: client).schedule(
        courses: [_course('a')],
        prefs: prefs,
        config: _config(),
        localeCode: 'zh-CN',
      );
      final error = outcome as AiScheduleOutcomeError;
      expect(error.error.type, AiScheduleErrorType.parse);
    });

    test('AI 返回空顺序返回 empty 错误', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"order":[],"reason":"没有课程"}'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final outcome = await AiScheduler(client: client).schedule(
        courses: [_course('a')],
        prefs: prefs,
        config: _config(),
        localeCode: 'zh-CN',
      );
      final error = outcome as AiScheduleOutcomeError;
      expect(error.error.type, AiScheduleErrorType.empty);
    });
  });

  group('AiScheduleSettings', () {
    test('startMode 默认与序列化', () {
      const prefs = AiSchedulePrefs();
      expect(prefs.startMode, ScheduleStartMode.now);
      final loaded = AiSchedulePrefs.fromJson(prefs.toJson());
      expect(loaded.startMode, ScheduleStartMode.now);
      const tomorrow = AiSchedulePrefs(startMode: ScheduleStartMode.tomorrow);
      expect(
        AiSchedulePrefs.fromJson(tomorrow.toJson()).startMode,
        ScheduleStartMode.tomorrow,
      );
    });

    test('保存并读回上次排课设置', () async {
      final settings = AiScheduleSettings(secretStore: _FakeSecretStore());
      expect(await settings.loadSetupPrefs(), isNull);
      await settings.saveSetupPrefs(
        const AiSchedulePrefs(
          intensity: StudyIntensity.stressed,
          days: 5,
          notes: '周三有会',
          timePreference: '上午',
        ),
      );
      final loaded = await settings.loadSetupPrefs();
      expect(loaded, isNotNull);
      expect(loaded!.intensity, StudyIntensity.stressed);
      expect(loaded.days, 5);
      expect(loaded.notes, '周三有会');
      expect(loaded.timePreference, '上午');
    });

    test('配置读写（API Key 走加密存储）', () async {
      final store = _FakeSecretStore();
      final settings = AiScheduleSettings(secretStore: store);
      await settings.saveConfig(
        provider: AiProvider.openai,
        baseUrl: 'https://custom.example.com/v1',
        model: 'gpt-test',
        apiKey: 'sk-secret',
      );
      final loaded = await settings.loadConfig(
        windowDescription: '09:00-18:00',
      );
      expect(loaded.provider, AiProvider.openai);
      expect(loaded.baseUrl, 'https://custom.example.com/v1');
      expect(loaded.model, 'gpt-test');
      expect(loaded.apiKey, 'sk-secret');
      expect(loaded.windowDescription, '09:00-18:00');
      expect(store.aiKey, 'sk-secret');
    });
  });

  group('parseNotesTimeRanges', () {
    test('解析学习时段与不可用时段（用户实例）', () {
      final parsed = parseNotesTimeRanges(
        '9点到12点，13点半到晚上9点学习，下午1点到6点有事',
      );
      expect(parsed.learning, [
        (9 * 60, 12 * 60),
        (13 * 60 + 30, 21 * 60),
      ]);
      expect(parsed.blocked, [(13 * 60, 18 * 60)]);
    });

    test('无关键词时段默认视为学习时段', () {
      final parsed = parseNotesTimeRanges('9:00-12:00 与 14:00-18:00');
      expect(parsed.learning, [
        (9 * 60, 12 * 60),
        (14 * 60, 18 * 60),
      ]);
      expect(parsed.blocked, isEmpty);
    });

    test('空备注返回空', () {
      final parsed = parseNotesTimeRanges('');
      expect(parsed.learning, isEmpty);
      expect(parsed.blocked, isEmpty);
    });

    test('"不学习"时段归入不可用（午休）', () {
      final parsed = parseNotesTimeRanges(
        '早上9点到晚上9点,中午12点到下午1点半不学习',
      );
      expect(parsed.learning, [(9 * 60, 21 * 60)]);
      expect(parsed.blocked, [(12 * 60, 13 * 60 + 30)]);
    });

    test('下午时段 +12 小时（下午1点到6点有事）', () {
      final parsed = parseNotesTimeRanges('9点到12点，下午1点到6点有事');
      expect(parsed.learning, [(9 * 60, 12 * 60)]);
      expect(parsed.blocked, [(13 * 60, 18 * 60)]);
    });

    test('不包含时间段时返回空', () {
      final parsed = parseNotesTimeRanges('周三晚上有会');
      expect(parsed.learning, isEmpty);
      expect(parsed.blocked, isEmpty);
    });
  });

  group('AiUsageStats', () {
    test('按模型累计 token 与请求次数', () async {
      await AiUsageStats.instance.debugReset();
      await AiUsageStats.instance.record(
        provider: AiProvider.deepseek,
        model: 'deepseek-v4-flash',
        promptTokens: 100,
        completionTokens: 50,
      );
      await AiUsageStats.instance.record(
        provider: AiProvider.deepseek,
        model: 'deepseek-v4-flash',
        promptTokens: 200,
        completionTokens: 100,
      );
      await AiUsageStats.instance.record(
        provider: AiProvider.openai,
        model: 'gpt-5.6-sol',
        promptTokens: 10,
        completionTokens: 5,
      );
      final entries = AiUsageStats.instance.entries;
      expect(entries, hasLength(2));
      final flash = entries.singleWhere((e) => e.model == 'deepseek-v4-flash');
      expect(flash.requests, 2);
      expect(flash.promptTokens, 300);
      expect(flash.completionTokens, 150);
      expect(AiUsageStats.instance.totalTokens, 465);
      expect(AiUsageStats.instance.totalRequests, 3);
      // 花费为正的估算值。
      expect(AiUsageStats.instance.totalCostUsd, greaterThan(0));
    });

    test('估算花费按模型价格计算', () {
      const usage = AiModelUsage(
        provider: 'deepseek',
        model: 'deepseek-v4-flash',
        requests: 1,
        promptTokens: 1000000,
        completionTokens: 1000000,
      );
      expect(estimateCostInUsd(usage), closeTo(0.5, 0.001));
    });
  });

  group('availabilityFromDayWindow', () {    test('正常午休拆分为两个时段', () {
      final days = availabilityFromDayWindow(
        startMinute: 8 * 60,
        lunchStartMinute: 12 * 60,
        lunchEndMinute: 13 * 60,
        endMinute: 22 * 60,
      );
      expect(days, hasLength(7));
      final slots = days.first;
      expect(slots, hasLength(2));
      expect(slots[0].startMinute, 8 * 60);
      expect(slots[0].endMinute, 12 * 60);
      expect(slots[1].startMinute, 13 * 60);
      expect(slots[1].endMinute, 22 * 60);
    });

    test('午休无效时退化为单时段', () {
      final days = availabilityFromDayWindow(
        startMinute: 8 * 60,
        lunchStartMinute: 8 * 60,
        lunchEndMinute: 8 * 60,
        endMinute: 22 * 60,
      );
      final slots = days.first;
      expect(slots, hasLength(1));
      expect(slots.single.startMinute, 8 * 60);
      expect(slots.single.endMinute, 22 * 60);
    });

    test('支持非整点时间', () {
      final days = availabilityFromDayWindow(
        startMinute: 8 * 60 + 30,
        lunchStartMinute: 12 * 60 + 15,
        lunchEndMinute: 13 * 60 + 45,
        endMinute: 22 * 60 + 10,
      );
      final slots = days.first;
      expect(slots[0].startMinute, 8 * 60 + 30);
      expect(slots[0].endMinute, 12 * 60 + 15);
      expect(slots[1].startMinute, 13 * 60 + 45);
      expect(slots[1].endMinute, 22 * 60 + 10);
    });
  });
}
