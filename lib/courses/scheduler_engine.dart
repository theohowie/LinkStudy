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

/// AI 排课顺序项：课程 id + 课后休息分钟（AI 决定休息时长，本地落位时并入占用）。
typedef OrderedCourse = ({String courseId, int restAfterMinutes});

/// 对"待安排"课程执行自动排课。
///
/// [pending] 待安排课程；[availabilityByWeekday] 每天可用时段（index 0=周一 … 6=周日）；
/// [occupied] 已占用区间（weekday → 起止分钟列表，含锁定槽位）；[today] 今天（锚定排课日期）。
/// [ordered] 可选：AI 给出的课程顺序与课后休息，提供时优先按此顺序落位（未覆盖的课程按默认排序补排）；
/// [horizonDays] 排课窗口天数（默认 7；AI 排课按"计划天数"传入）。
/// [startFromNow] 是否从当前时刻开始排（true=裁剪今天已过时段，避免排到过去；
/// false=今天全天可用，配合"从明天开始"时将 [today] 传为明天）。
SchedulingResult scheduleCourses({
  required List<LinkCourse> pending,
  required List<List<AvailabilitySlot>> availabilityByWeekday,
  required Map<int, List<({int start, int end})>> occupied,
  required DateTime today,
  List<OrderedCourse>? ordered,
  int horizonDays = 7,
  bool startFromNow = true,
}) {
  if (pending.isEmpty) {
    return const SchedulingResult(placements: [], failures: []);
  }

  // 排序：优先 AI 顺序（ordered 内按序，未覆盖的按默认排序补排）；
  // 无 ordered 时默认：截止升序 → 优先级降序 → 录入升序。
  final sorted = _orderPending(pending, ordered);

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
      horizonDays: horizonDays,
      startFromNow: startFromNow,
    );
    if (placed == null) {
      failures.add((
        courseId: course.id,
        reason: '《${course.title}》时长 ${course.durationMinutes} 分钟，未来 $horizonDays 天无足够空档',
      ));
      continue;
    }
    placements.add(placed);
    // 课后休息并入占用：AI 建议的休息在时段内生效；clamp 0-120 防止过大休息挤掉课程。
    final rest = _restAfterFor(course.id, ordered).clamp(0, 120);
    (occ[placed.weekday] ??= []).add(
      (start: placed.start, end: placed.end + rest),
    );
    occ[placed.weekday] = _sortedOccupied(occ[placed.weekday]);
  }

  return SchedulingResult(placements: placements, failures: failures);
}

/// 按 AI 顺序（含未覆盖补排）整理待排课程。
List<LinkCourse> _orderPending(
  List<LinkCourse> pending,
  List<OrderedCourse>? ordered,
) {
  final sorted = [...pending]..sort(_defaultOrder);
  if (ordered == null || ordered.isEmpty) {
    return sorted;
  }
  final orderIndex = <String, int>{
    for (var i = 0; i < ordered.length; i++) ordered[i].courseId: i,
  };
  final inOrder = sorted.where((c) => orderIndex.containsKey(c.id)).toList()
    ..sort((a, b) => orderIndex[a.id]!.compareTo(orderIndex[b.id]!));
  final rest = sorted.where((c) => !orderIndex.containsKey(c.id)).toList();
  return [...inOrder, ...rest];
}

int _defaultOrder(LinkCourse a, LinkCourse b) {
  final byDeadline = _deadlineValue(a).compareTo(_deadlineValue(b));
  if (byDeadline != 0) return byDeadline;
  final byPriority =
      priorityWeight(b.priority).compareTo(priorityWeight(a.priority));
  if (byPriority != 0) return byPriority;
  return a.createdAt.compareTo(b.createdAt);
}

int _restAfterFor(String courseId, List<OrderedCourse>? ordered) {
  if (ordered == null) return 0;
  for (final item in ordered) {
    if (item.courseId == courseId) return item.restAfterMinutes;
  }
  return 0;
}

/// 尝试为课程放置槽位；失败返回 null。
SchedulePlacement? _placeCourse(
  LinkCourse course, {
  required Map<int, List<({int start, int end})>> occupied,
  required List<List<AvailabilitySlot>> availabilityByWeekday,
  required DateTime today,
  required int horizonDays,
  required bool startFromNow,
}) {
  final duration = course.durationMinutes;
  if (duration <= 0) return null;

  final todayWeekday = today.weekday;
  final todayMinute = today.hour * 60 + today.minute;
  for (var offset = 0; offset < horizonDays; offset++) {
    final weekday = ((todayWeekday - 1 + offset) % 7) + 1;
    final rawAvailability = availabilityByWeekday.length >= weekday
        ? availabilityByWeekday[weekday - 1]
        : const <AvailabilitySlot>[];
    // 从当前时刻开始排：裁剪今天（offset 0）已过的时间段，避免排到过去。
    final dayAvailability = offset == 0 && startFromNow
        ? [
            for (final seg in rawAvailability)
              if (seg.endMinute > todayMinute)
                AvailabilitySlot(
                  startMinute:
                      seg.startMinute < todayMinute ? todayMinute : seg.startMinute,
                  endMinute: seg.endMinute,
                ),
          ]
        : rawAvailability;
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
