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

    test('F4-7: AI 顺序优先于默认排序', () {
      final result = scheduleCourses(
        pending: [
          course(id: 'later', deadline: 20),
          course(id: 'sooner', deadline: 2),
        ],
        availabilityByWeekday: availability,
        occupied: const {},
        today: today,
        ordered: [
          (courseId: 'later', restAfterMinutes: 0),
          (courseId: 'sooner', restAfterMinutes: 0),
        ],
      );
      expect(result.failures, isEmpty);
      final later = result.placements.firstWhere((p) => p.courseId == 'later');
      final sooner = result.placements.firstWhere((p) => p.courseId == 'sooner');
      // AI 顺序让 later 先占今天 19:00，sooner 只能排到其后。
      expect(later.start, 19 * 60);
      expect(sooner.start, greaterThan(later.start));
    });

    test('F4-8: 课后休息并入占用，后续课程不会紧贴', () {
      final result = scheduleCourses(
        pending: [
          course(id: 'a', duration: 40),
          course(id: 'b', duration: 40),
          course(id: 'c', duration: 40),
        ],
        availabilityByWeekday: availability,
        occupied: const {},
        today: today,
        ordered: const [
          (courseId: 'a', restAfterMinutes: 30),
          (courseId: 'b', restAfterMinutes: 30),
          (courseId: 'c', restAfterMinutes: 0),
        ],
      );
      expect(result.failures, isEmpty);
      final byId = {
        for (final p in result.placements) p.courseId: p,
      };
      expect(byId['a']!.start, 19 * 60);
      // a 结束 19:40 + 休息 30 → b 从 20:10 开始。
      expect(byId['b']!.start, 20 * 60 + 10);
      // b 结束 20:50 + 休息 30 → c 从 21:20 开始。
      expect(byId['c']!.start, 21 * 60 + 20);
    });

    test('F4-9: 计划天数窗口生效（今天占满时 1 天失败、7 天成功）', () {
      const fullToday = {
        1: [(start: 19 * 60, end: 22 * 60)],
      };
      final oneDay = scheduleCourses(
        pending: [course(id: 'a', duration: 40)],
        availabilityByWeekday: availability,
        occupied: fullToday,
        today: today,
        horizonDays: 1,
      );
      expect(oneDay.placements, isEmpty);
      expect(oneDay.failures, hasLength(1));

      final sevenDays = scheduleCourses(
        pending: [course(id: 'a', duration: 40)],
        availabilityByWeekday: availability,
        occupied: fullToday,
        today: today,
        horizonDays: 7,
      );
      expect(sevenDays.placements, hasLength(1));
      // 今天周一占满 → 顺延到周二。
      expect(sevenDays.placements.single.weekday, 2);
    });

    test('F4-10: 从现在开始——今天已过时段不排（顺延明天）', () {
      // 周一 23:30，时段 19:00-22:00 已全部过去。
      final lateToday = DateTime(2026, 1, 5, 23, 30);
      final result = scheduleCourses(
        pending: [course(id: 'a', duration: 40)],
        availabilityByWeekday: availability,
        occupied: const {},
        today: lateToday,
        startFromNow: true,
      );
      expect(result.placements, hasLength(1));
      expect(result.placements.single.weekday, 2);
      expect(result.placements.single.day, epochDayOf(DateTime(2026, 1, 6)));
    });

    test('F4-11: 从现在开始——今天部分时段已过则从当前时刻起排', () {
      // 周一 20:00，时段 19:00-22:00 已过 1 小时。
      final today = DateTime(2026, 1, 5, 20, 0);
      final result = scheduleCourses(
        pending: [course(id: 'a', duration: 40)],
        availabilityByWeekday: availability,
        occupied: const {},
        today: today,
        startFromNow: true,
      );
      expect(result.placements.single.start, 20 * 60);
    });

    test('F4-12: 从明天开始——今天不排，从明天起排', () {
      // 周一 10:00，"今天"传为明天（周二），不裁剪时段。
      final today = DateTime(2026, 1, 5, 10, 0);
      final result = scheduleCourses(
        pending: [course(id: 'a', duration: 40)],
        availabilityByWeekday: availability,
        occupied: const {},
        today: today.add(const Duration(days: 1)),
        startFromNow: false,
      );
      expect(result.placements, hasLength(1));
      expect(result.placements.single.weekday, 2);
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
