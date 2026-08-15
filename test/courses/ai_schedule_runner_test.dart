import 'package:flutter_test/flutter_test.dart';
import 'package:linkstudy/courses/ai_schedule_runner.dart';
import 'package:linkstudy/courses/ai_scheduler.dart';
import 'package:linkstudy/courses/link_course.dart';
import 'package:linkstudy/services/notification_service.dart';
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
  }) async {
    return outcome;
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
}
