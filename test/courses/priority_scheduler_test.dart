import 'package:flutter_test/flutter_test.dart';
import 'package:linkstudy/courses/priority_scheduler.dart';

void main() {
  group('算法一：AHP 优先系数', () {
    test('2x2 一致矩阵权重归一化且和为 1', () {
      final w = ahpWeights(importanceOverDifficulty: 3);
      expect(w.importance, closeTo(0.75, 1e-9));
      expect(w.difficulty, closeTo(0.25, 1e-9));
      expect(w.importance + w.difficulty, closeTo(1.0, 1e-9));
    });

    test('a=1 时两因子等权', () {
      final w = ahpWeights(importanceOverDifficulty: 1);
      expect(w.importance, closeTo(0.5, 1e-9));
      expect(w.difficulty, closeTo(0.5, 1e-9));
    });

    test('难度更高、更重要、更临近截止的课程优先系数更大', () {
      double p({
        required double difficulty,
        required double importance,
        int? deadlineDays,
      }) =>
          priorityCoefficient(
            difficulty: difficulty,
            importance: importance,
            deadlineDays: deadlineDays,
            minDifficulty: 1,
            maxDifficulty: 9,
            minImportance: 1,
            maxImportance: 9,
            minUrgency: 0,
            maxUrgency: 1,
          );

      final hardImportantUrgent =
          p(difficulty: 9, importance: 9, deadlineDays: 1);
      final easyLowNoDeadline =
          p(difficulty: 1, importance: 1, deadlineDays: null);
      expect(hardImportantUrgent, greaterThan(easyLowNoDeadline));

      // 截止越近越高（其余相同）。
      final urgent = p(difficulty: 5, importance: 5, deadlineDays: 1);
      final relaxed = p(difficulty: 5, importance: 5, deadlineDays: 30);
      expect(urgent, greaterThan(relaxed));

      // 重要程度主导：a=3 时重要程度高者优先系数更大。
      final highImportance = p(difficulty: 3, importance: 9, deadlineDays: 10);
      final highDifficulty = p(difficulty: 9, importance: 3, deadlineDays: 10);
      expect(highImportance, greaterThan(highDifficulty));
    });
  });

  group('算法二：可用时间片生成', () {
    test('切分 + 不可用时间排除', () {
      final slices = availableSlices(
        dayStart: 8 * 60,
        dayEnd: 12 * 60,
        sliceMinutes: 30,
        blocked: const [
          (start: 9 * 60, end: 10 * 60),
        ],
      );
      expect(slices, [
        (start: 8 * 60, end: 8 * 60 + 30),
        (start: 8 * 60 + 30, end: 9 * 60),
        (start: 10 * 60, end: 10 * 60 + 30),
        (start: 10 * 60 + 30, end: 11 * 60),
        (start: 11 * 60, end: 11 * 60 + 30),
        (start: 11 * 60 + 30, end: 12 * 60),
      ]);
    });

    test('多个不可用时间段与尾部截断', () {
      final slices = availableSlices(
        dayStart: 8 * 60,
        dayEnd: 22 * 60,
        sliceMinutes: 30,
        blocked: const [
          (start: 9 * 60, end: 9 * 60 + 30),
          (start: 12 * 60, end: 13 * 60),
          (start: 21 * 60, end: 22 * 60),
        ],
      );
      expect(slices.first, (start: 8 * 60, end: 8 * 60 + 30));
      expect(slices, isNot(contains((start: 9 * 60, end: 9 * 60 + 30))));
      expect(slices, isNot(contains((start: 12 * 60, end: 12 * 60 + 30))));
      expect(slices.last.end, 21 * 60);
    });
  });

  group('算法三+四：贪心分配调度', () {
    final dayStart = 8 * 60;
    final dayEnd = 22 * 60;

    PriorityScheduleResult runSchedule({
      required List<PriorityCourse> courses,
      int horizonDays = 7,
      List<List<({int start, int end})>>? blockedByDay,
      List<List<({int start, int end})>>? peaksByDay,
    }) =>
        const PriorityScheduler().run(
          courses: courses,
          horizonDays: horizonDays,
          dayStart: dayStart,
          dayEnd: dayEnd,
          blockedByDay: blockedByDay ?? const [],
          peaksByDay: peaksByDay,
        );

    test('按优先系数降序排课，全部落位', () {
      final result = runSchedule(
        courses: [
          PriorityCourse(
            id: 'a',
            title: '高优先难课',
            durationMinutes: 40,
            priority: 0.9,
            intensity: IntensityLevel.high,
          ),
          PriorityCourse(
            id: 'b',
            title: '中优先课',
            durationMinutes: 40,
            priority: 0.5,
            intensity: IntensityLevel.medium,
          ),
          PriorityCourse(
            id: 'c',
            title: '低优先轻松课',
            durationMinutes: 40,
            priority: 0.1,
            intensity: IntensityLevel.light,
          ),
        ],
      );
      expect(result.allScheduled, isTrue);
      // 全部课程都至少有一块。
      final placedIds = result.placements.map((p) => p.courseId).toSet();
      expect(placedIds, {'a', 'b', 'c'});
      // 高优先课程占据最早的可用块。
      final first = result.placements.first;
      expect(first.courseId, 'a');
      expect(first.start, dayStart);
    });

    test('高强度档：单块不超过 T_max、每日不超过 D_max、优先峰值时段', () {
      final result = runSchedule(
        courses: [
          // 120 分钟高强度课：T_max=50 → 拆成 3 块（50+50+20），
          // D_max=90 → 每天最多 90，至少跨 2 天。
          PriorityCourse(
            id: 'x',
            title: '高强度长课',
            durationMinutes: 120,
            priority: 1.0,
            intensity: IntensityLevel.high,
          ),
        ],
        peaksByDay: [
          for (var d = 0; d < 7; d++)
            const [(start: 9 * 60, end: 11 * 60)],
        ],
      );
      expect(result.allScheduled, isTrue);
      expect(result.placements, hasLength(3));
      final byDay = <int, List<Placement>>{};
      for (final p in result.placements) {
        byDay.putIfAbsent(p.day, () => []).add(p);
      }
      expect(byDay.length, greaterThanOrEqualTo(2), reason: '应跨天分配');
      for (final p in result.placements) {
        expect(p.end - p.start, lessThanOrEqualTo(50), reason: 'T_max 上限');
        // 峰值时段内（9:00-11:00）。
        expect(p.start, greaterThanOrEqualTo(9 * 60));
        expect(p.end, lessThanOrEqualTo(11 * 60));
      }
      for (final day in byDay.values) {
        final total = day.fold(0, (s, p) => s + (p.end - p.start));
        expect(total, lessThanOrEqualTo(90), reason: 'D_max 上限');
      }
    });

    test('中等档：间隔重复（隔天分散）', () {
      final result = runSchedule(
        courses: [
          PriorityCourse(
            id: 'm',
            title: '复习课',
            durationMinutes: 90,
            priority: 0.5,
            intensity: IntensityLevel.medium,
          ),
        ],
      );
      expect(result.allScheduled, isTrue);
      // chunk=30 → 3 块；intervalDays=1 → 间隔至少隔一天。
      expect(result.placements, hasLength(3));
      final days = result.placements.map((p) => p.day).toList()..sort();
      expect(days[1] - days[0], greaterThanOrEqualTo(2));
      expect(days[2] - days[1], greaterThanOrEqualTo(2));
    });

    test('时间不足时按优先系数降序保高弃低，并报告失败', () {
      final result = runSchedule(
        horizonDays: 1,
        blockedByDay: [
          const [(start: 9 * 60, end: 21 * 60)], // 只剩 8-9 与 21-22
        ],
        courses: [
          PriorityCourse(
            id: 'big',
            title: '低优先超长课',
            durationMinutes: 200,
            priority: 0.1,
            intensity: IntensityLevel.light,
          ),
          PriorityCourse(
            id: 'small',
            title: '高优先短课',
            durationMinutes: 30,
            priority: 0.9,
            intensity: IntensityLevel.light,
          ),
        ],
      );
      expect(result.allScheduled, isFalse);
      expect(result.placements.map((p) => p.courseId), contains('small'));
      expect(result.failures.map((f) => f.courseId), contains('big'));
    });
  });
}
