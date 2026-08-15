import 'package:flutter_test/flutter_test.dart';
import 'package:linkstudy/courses/link_course.dart';
import 'package:linkstudy/courses/scheduler_engine.dart';

LinkCourse course({
  required String id,
  int duration = 40,
  int? deadline,
  CoursePriority priority = CoursePriority.medium,
  int created = 0,
}) {
  return LinkCourse(
    id: id,
    url: 'https://example.com/$id',
    title: '课程$id',
    durationMinutes: duration,
    createdAt: DateTime(2026, 1, 1).add(Duration(minutes: created)),
    deadlineDay: deadline,
    priority: priority,
  );
}

void main() {
  // 默认每天 19:00-22:00（180 分钟），今天=周一（2026-01-05）。
  final availability = List.generate(7, (_) => defaultAvailability());
  final today = DateTime(2026, 1, 5);

  group('scheduler_engine', () {
    test('F4-1: 排课结果无时间重叠', () {
      final result = scheduleCourses(
        pending: [
          course(id: 'a', duration: 60),
          course(id: 'b', duration: 60),
          course(id: 'c', duration: 60),
        ],
        availabilityByWeekday: availability,
        occupied: const {},
        today: today,
      );
      expect(result.failures, isEmpty);
      expect(result.placements, hasLength(3));
      final byDay = <int, List<({int start, int end})>>{};
      for (final p in result.placements) {
        (byDay[p.weekday] ??= []).add((start: p.start, end: p.end));
      }
      for (final day in byDay.values) {
        day.sort((a, b) => a.start.compareTo(b.start));
        for (var i = 1; i < day.length; i++) {
          expect(day[i].start, greaterThanOrEqualTo(day[i - 1].end));
        }
      }
    });

    test('F4-2: 截止日期最近的课程优先获得最早空档', () {
      final result = scheduleCourses(
        pending: [
          course(id: 'later', deadline: 20),
          course(id: 'sooner', deadline: 2),
        ],
        availabilityByWeekday: availability,
        occupied: const {},
        today: today,
      );
      final sooner = result.placements.firstWhere((p) => p.courseId == 'sooner');
      final later = result.placements.firstWhere((p) => p.courseId == 'later');
      expect(
        sooner.weekday * 10000 + sooner.start,
        lessThanOrEqualTo(later.weekday * 10000 + later.start),
      );
    });

    test('F4-3: 已占用槽位保留且不重叠', () {
      final result = scheduleCourses(
        pending: [course(id: 'a', duration: 60), course(id: 'b', duration: 60)],
        availabilityByWeekday: availability,
        occupied: const {
          1: [(start: 19 * 60, end: 20 * 60)],
        },
        today: today,
      );
      expect(result.failures, isEmpty);
      for (final p in result.placements.where((p) => p.weekday == 1)) {
        expect(p.start < 20 * 60 && p.end > 19 * 60, isFalse);
      }
    });

    test('F4-4: 无足够空档返回可读失败原因', () {
      final result = scheduleCourses(
        pending: [course(id: 'tooLong', duration: 200)],
        availabilityByWeekday: availability,
        occupied: const {},
        today: today,
      );
      expect(result.placements, isEmpty);
      expect(result.failures, hasLength(1));
      expect(result.failures.single.courseId, 'tooLong');
      expect(result.failures.single.reason, contains('无足够空档'));
    });

    test('F4-5: 未配置可用时段时全部留在待安排', () {
      final result = scheduleCourses(
        pending: [course(id: 'a', duration: 40)],
        availabilityByWeekday:
            List.generate(7, (_) => const <AvailabilitySlot>[]),
        occupied: const {},
        today: today,
      );
      expect(result.placements, isEmpty);
      expect(result.failures, hasLength(1));
    });

    test('F4-6: 排课结果携带具体日期（epochDay 自今天起）', () {
      final result = scheduleCourses(
        pending: [course(id: 'a', duration: 40)],
        availabilityByWeekday: availability,
        occupied: const {},
        today: today,
      );
      expect(result.placements, hasLength(1));
      final p = result.placements.single;
      // 今天周一无占用 → 第一个空档就在今天 19:00。
      expect(p.weekday, 1);
      expect(p.day, epochDayOf(DateTime(2026, 1, 5)));
    });

    test('空待安排返回空结果', () {
      final result = scheduleCourses(
        pending: const [],
        availabilityByWeekday: availability,
        occupied: const {},
        today: today,
      );
      expect(result.placements, isEmpty);
      expect(result.failures, isEmpty);
    });
  });
}
