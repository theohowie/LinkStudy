import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkstudy/courses/ai_schedule_runner.dart';
import 'package:linkstudy/courses/ai_scheduler.dart';
import 'package:linkstudy/courses/link_course.dart';
import 'package:linkstudy/services/notification_service.dart';
import 'package:linkstudy/widgets/ai_schedule_progress_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeScheduler extends AiScheduler {
  _FakeScheduler(this.outcome);

  final AiScheduleOutcome outcome;

  @override
  Future<AiScheduleOutcome> schedule({
    required List<LinkCourse> courses,
    required AiSchedulePrefs prefs,
    required AiScheduleConfig config,
    required String localeCode,
    void Function(String delta)? onToken,
    void Function(int promptTokens, int completionTokens)? onUsage,
  }) async {
    return outcome;
  }
}

/// 流式测试调度器：schedule 挂起直到 [complete] 被调用，
/// 期间可通过 [emit] 逐块推送 AI 输出（模拟 SSE 实时流）。
class _StreamingScheduler extends AiScheduler {
  _StreamingScheduler();

  final List<void Function(String)> _onToken = [];
  final Completer<void> _scheduled = Completer<void>();
  Completer<AiScheduleOutcome>? _completer;

  /// schedule() 是否已注册 onToken 回调（此时 emit 才会生效）。
  bool get isScheduled => _scheduled.isCompleted;

  @override
  Future<AiScheduleOutcome> schedule({
    required List<LinkCourse> courses,
    required AiSchedulePrefs prefs,
    required AiScheduleConfig config,
    required String localeCode,
    void Function(String delta)? onToken,
    void Function(int promptTokens, int completionTokens)? onUsage,
  }) async {
    if (onToken != null) _onToken.add(onToken);
    if (!_scheduled.isCompleted) _scheduled.complete();
    final completer = Completer<AiScheduleOutcome>();
    _completer = completer;
    return completer.future;
  }

  void emit(String delta) {
    for (final cb in _onToken) {
      cb(delta);
    }
  }

  void complete(AiScheduleOutcome outcome) {
    _completer?.complete(outcome);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LinkCourseStore.instance.debugSkipPersist = true;
    LinkCourseStore.instance.debugClear();
    AiScheduleRunner.instance.debugReset();
    NotificationService.instance.debugSkipSend = true;
  });

  final availability = availabilityFromDayWindow(
    startMinute: 8 * 60,
    lunchStartMinute: 12 * 60,
    lunchEndMinute: 13 * 60,
    endMinute: 22 * 60,
  );

  Future<LinkCourse> addCourse(String id) => LinkCourseStore.instance.addCourse(
        url: 'https://example.com/$id',
        title: '课程$id',
        durationMinutes: 40,
      );

  test('成功路径：任务完成、课程落位、状态更新', () async {
    final store = LinkCourseStore.instance;
    final a = await addCourse('a');
    final b = await addCourse('b');

    await AiScheduleRunner.instance.start(
      courseIds: [a.id, b.id],
      prefs: const AiSchedulePrefs(days: 3),
      availability: availability,
      windowDescription: '08:00-12:00 与 13:00-22:00',
      localeCode: 'zh-CN',
      scheduler: _FakeScheduler(
        const AiScheduleOutcomeSuccess(
          AiScheduleSuccess(
            ordered: [
              (courseId: 'a', restAfterMinutes: 10),
              (courseId: 'b', restAfterMinutes: 0),
            ],
            reason: '按截止日期优先安排',
          ),
        ),
      ),
    );

    final task = AiScheduleRunner.instance.task!;
    expect(task.phase, AiSchedulePhase.done);
    expect(task.aiReason, '按截止日期优先安排');
    expect(task.placedCount, 2);
    expect(task.failureCount, 0);
    expect(store.slots, hasLength(2));
    expect(store.pendingCount, 0);
    expect(AiScheduleRunner.instance.isRunning, isFalse);
    expect(AiScheduleRunner.instance.hasUnviewedResult, isTrue);
  });

  test('失败路径：任务失败、课程留在未排课池', () async {
    final store = LinkCourseStore.instance;
    final a = await addCourse('a');

    await AiScheduleRunner.instance.start(
      courseIds: [a.id],
      prefs: const AiSchedulePrefs(),
      availability: availability,
      windowDescription: '08:00-12:00 与 13:00-22:00',
      localeCode: 'zh-CN',
      scheduler: _FakeScheduler(
        const AiScheduleOutcomeError(
          AiScheduleError(
            type: AiScheduleErrorType.network,
            message: '网络连接失败',
          ),
        ),
      ),
    );

    final task = AiScheduleRunner.instance.task!;
    expect(task.phase, AiSchedulePhase.failed);
    expect(task.error, contains('网络连接失败'));
    expect(store.slots, isEmpty);
    expect(store.pendingCount, 1);
    expect(AiScheduleRunner.instance.hasUnviewedResult, isTrue);
  });

  test('markViewed 后 hasUnviewedResult 为 false', () async {
    final store = LinkCourseStore.instance;
    final a = await addCourse('a');

    await AiScheduleRunner.instance.start(
      courseIds: [a.id],
      prefs: const AiSchedulePrefs(),
      availability: availability,
      windowDescription: '08:00-12:00 与 13:00-22:00',
      localeCode: 'zh-CN',
      scheduler: _FakeScheduler(
        const AiScheduleOutcomeSuccess(
          AiScheduleSuccess(
            ordered: [(courseId: 'a', restAfterMinutes: 0)],
            reason: '',
          ),
        ),
      ),
    );

    expect(AiScheduleRunner.instance.hasUnviewedResult, isTrue);
    AiScheduleRunner.instance.markViewed();
    expect(AiScheduleRunner.instance.hasUnviewedResult, isFalse);
  });

  testWidgets('对话视图在排课中实时流式展示 AI 输出', (tester) async {
    // start() 的 await 链会调用原生 MethodChannel（悬浮窗权限、secure storage），
    // FakeAsync 下无 mock 会永远挂起，这里全部接管并立即返回。
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.theohowie.linkstudy.overlay'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );

    final store = LinkCourseStore.instance;
    await addCourse('a');
    await addCourse('b');
    final scheduler = _StreamingScheduler();

    final taskFuture = AiScheduleRunner.instance.start(
      courseIds: ['a', 'b'],
      prefs: const AiSchedulePrefs(days: 3),
      availability: availability,
      windowDescription: '08:00-12:00 与 13:00-22:00',
      localeCode: 'zh-CN',
      scheduler: scheduler,
    );

    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiScheduleConversation(store: store),
          ),
        ),
      ),
    );
    await tester.pump();

    // 排课中：展示用户请求气泡 + AI 思考占位。
    expect(find.textContaining('帮我排课'), findsOneWidget);
    expect(find.textContaining('正在思考排课方案'), findsOneWidget);

    // 等待 schedule() 注册 onToken，确保 emit 生效。
    for (var i = 0; i < 50 && !scheduler.isScheduled; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(scheduler.isScheduled, isTrue, reason: 'schedule() 应已被调用');

    // 流式推送第一块：AI 输出实时出现。
    scheduler.emit('先按截止日期排序');
    await tester.pump();
    expect(find.textContaining('先按截止日期排序'), findsOneWidget);

    // 再推送一块：累积展示。
    scheduler.emit('，然后均摊到每天');
    await tester.pump();
    expect(find.textContaining('先按截止日期排序，然后均摊到每天'), findsOneWidget);

    // 完成：展示思路与课程安排。
    scheduler.complete(
      const AiScheduleOutcomeSuccess(
        AiScheduleSuccess(
          ordered: [
            (courseId: 'a', restAfterMinutes: 10),
            (courseId: 'b', restAfterMinutes: 0),
          ],
          reason: '按截止日期优先安排',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('按截止日期优先安排'), findsOneWidget);
    expect(find.text('课程安排'), findsOneWidget);
    expect(find.textContaining('未排上'), findsNothing);

    await taskFuture;
  });
}
