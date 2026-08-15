import 'package:flutter_test/flutter_test.dart';
import 'package:linkstudy/courses/link_course.dart';

void main() {
  final availability = availabilityFromDayWindow(
    startHour: 8,
    lunchStartHour: 12,
    lunchEndHour: 13,
    endHour: 22,
  );

  group('LinkCourseStore 入池与排课', () {
    test('addCourse 后进入未排课池，不自动排课', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final course = await store.addCourse(
        url: 'https://example.com/1',
        title: '考研英语',
        durationMinutes: 40,
      );
      expect(store.pendingCount, 1);
      expect(store.slots, isEmpty);
      expect(store.courseById(course.id), isNotNull);
    });

    test('scheduleWithOrder 按 AI 顺序落位并清空池子', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final a = await store.addCourse(
        url: 'https://example.com/a',
        title: '课程A',
        durationMinutes: 40,
      );
      final b = await store.addCourse(
        url: 'https://example.com/b',
        title: '课程B',
        durationMinutes: 40,
      );
      final result = await store.scheduleWithOrder(
        courseIds: [a.id, b.id],
        ordered: [
          (courseId: a.id, restAfterMinutes: 20),
          (courseId: b.id, restAfterMinutes: 0),
        ],
        days: 7,
        availabilityByWeekday: availability,
      );
      expect(result.failures, isEmpty);
      expect(result.placements, hasLength(2));
      expect(store.slots, hasLength(2));
      expect(store.pendingCount, 0);
      final aSlot = store.slots.singleWhere((s) => s.courseId == a.id);
      final bSlot = store.slots.singleWhere((s) => s.courseId == b.id);
      expect(aSlot.epochDay, isNotNull);
      // a 之后有 20 分钟休息 → b 不紧贴 a。
      expect(bSlot.startMinute, aSlot.endMinute + 20);
    });

    test('AI 失败回退：ordered 为空时按默认贪心落位', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final course = await store.addCourse(
        url: 'https://example.com/fallback',
        title: '回退课程',
        durationMinutes: 60,
      );
      final result = await store.scheduleWithOrder(
        courseIds: [course.id],
        ordered: const [],
        days: 7,
        availabilityByWeekday: availability,
      );
      expect(result.failures, isEmpty);
      expect(store.slots, hasLength(1));
      expect(store.pendingCount, 0);
    });

    test('schedulePending 贪心兜底仍可用', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      await store.addCourse(
        url: 'https://example.com/greedy',
        title: '贪心课程',
        durationMinutes: 40,
      );
      final result = await store.schedulePending();
      expect(result.failures, isEmpty);
      expect(store.slots, hasLength(1));
    });

    test('删除课程同时移除其槽位', () async {
      final store = LinkCourseStore.instance;
      store.debugClear();
      final course = await store.addCourse(
        url: 'https://example.com/del',
        title: '待删课程',
        durationMinutes: 40,
      );
      await store.schedulePending();
      expect(store.slots, hasLength(1));
      await store.deleteCourse(course.id);
      expect(store.courses, isEmpty);
      expect(store.slots, isEmpty);
    });
  });
}
