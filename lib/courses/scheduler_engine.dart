/// 自动排课引擎（纯函数领域层，不依赖 Flutter / 数据库）。
///
/// 贪心算法：
/// 1. 排序：截止日期升序（无截止视为 +∞）→ 优先级权重降序 → 录入顺序升序。
/// 2. 从今天起 7 天内为每门课找最早可放置的空档。
/// 3. 已占用槽位（含锁定）保留其时间，放不下的课程返回可读失败原因。
library;

import 'link_course.dart';

/// 优先级权重。
int priorityWeight(CoursePriority p) => switch (p) {
      CoursePriority.high => 3,
      CoursePriority.medium => 2,
      CoursePriority.low => 1,
    };

/// 默认可用时段（每天 19:00-22:00）。
List<AvailabilitySlot> defaultAvailability() =>
    const [AvailabilitySlot(startMinute: 19 * 60, endMinute: 22 * 60)];

/// 排课放置结果。[day] 为放置的具体日期（epochDay，自 1970-01-01 UTC 起的天数）。
typedef SchedulePlacement = ({
  String courseId,
  int day,
  int weekday,
  int start,
  int end,
});

/// 排课结果。
class SchedulingResult {
  final List<SchedulePlacement> placements;
  final List<({String courseId, String reason})> failures;

  const SchedulingResult({required this.placements, required this.failures});

  bool get allScheduled => failures.isEmpty;
}

/// 对"待安排"课程执行自动排课。
///
/// [pending] 待安排课程；[availabilityByWeekday] 每天可用时段（index 0=周一 … 6=周日）；
/// [occupied] 已占用区间（weekday → 起止分钟列表，含锁定槽位）；[today] 今天（锚定排课日期）。
SchedulingResult scheduleCourses({
  required List<LinkCourse> pending,
  required List<List<AvailabilitySlot>> availabilityByWeekday,
  required Map<int, List<({int start, int end})>> occupied,
  required DateTime today,
}) {
  if (pending.isEmpty) {
    return const SchedulingResult(placements: [], failures: []);
  }

  // 排序：截止升序 → 优先级降序 → 录入升序。
  final sorted = [...pending]..sort((a, b) {
      final byDeadline = _deadlineValue(a).compareTo(_deadlineValue(b));
      if (byDeadline != 0) return byDeadline;
      final byPriority =
          priorityWeight(b.priority).compareTo(priorityWeight(a.priority));
      if (byPriority != 0) return byPriority;
      return a.createdAt.compareTo(b.createdAt);
    });

  final placements = <SchedulePlacement>[];
  final failures = <({String courseId, String reason})>[];
  final occ = <int, List<({int start, int end})>>{
    for (final e in occupied.entries)
      e.key: _sortedOccupied(e.value),
  };

  for (final course in sorted) {
    final placed = _placeCourse(
      course,
      occupied: occ,
      availabilityByWeekday: availabilityByWeekday,
      today: today,
    );
    if (placed == null) {
      failures.add((
        courseId: course.id,
        reason: '《${course.title}》时长 ${course.durationMinutes} 分钟，未来 7 天无足够空档',
      ));
      continue;
    }
    placements.add(placed);
    (occ[placed.weekday] ??= []).add(
      (start: placed.start, end: placed.end),
    );
    occ[placed.weekday] = _sortedOccupied(occ[placed.weekday]);
  }

  return SchedulingResult(placements: placements, failures: failures);
}

/// 尝试为课程放置槽位；失败返回 null。
SchedulePlacement? _placeCourse(
  LinkCourse course, {
  required Map<int, List<({int start, int end})>> occupied,
  required List<List<AvailabilitySlot>> availabilityByWeekday,
  required DateTime today,
}) {
  final duration = course.durationMinutes;
  if (duration <= 0) return null;

  final todayWeekday = today.weekday;
  for (var offset = 0; offset < 7; offset++) {
    final weekday = ((todayWeekday - 1 + offset) % 7) + 1;
    final dayAvailability = availabilityByWeekday.length >= weekday
        ? availabilityByWeekday[weekday - 1]
        : const <AvailabilitySlot>[];
    for (final seg in dayAvailability) {
      if (seg.endMinute - seg.startMinute < duration) continue;
      final candidate = _firstFit(
        seg.startMinute,
        seg.endMinute,
        duration,
        occupied[weekday] ?? const [],
      );
      if (candidate != null) {
        return (
          courseId: course.id,
          day: epochDayOf(today) + offset,
          weekday: weekday,
          start: candidate.$1,
          end: candidate.$2,
        );
      }
    }
  }
  return null;
}

/// 在 [segStart, segEnd] 内找第一个可放下 [duration] 的起点（按占用边界切分）。
(int, int)? _firstFit(
  int segStart,
  int segEnd,
  int duration,
  List<({int start, int end})> occupied,
) {
  var cursor = segStart;
  for (final o in occupied) {
    if (o.end <= cursor) continue;
    if (o.start > cursor) {
      if (o.start - cursor >= duration) {
        return (cursor, cursor + duration);
      }
    }
    cursor = o.end > cursor ? o.end : cursor;
    if (cursor >= segEnd) break;
  }
  if (segEnd - cursor >= duration) {
    return (cursor, cursor + duration);
  }
  return null;
}

List<({int start, int end})> _sortedOccupied(
  List<({int start, int end})>? list,
) {
  final copy = [...?list]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <({int start, int end})>[];
  for (final o in copy) {
    if (merged.isEmpty || o.start >= merged.last.end) {
      merged.add(o);
    } else if (o.end > merged.last.end) {
      merged[merged.length - 1] = (start: merged.last.start, end: o.end);
    }
  }
  return merged;
}

int _deadlineValue(LinkCourse c) => c.deadlineDay ?? 1 << 30;
