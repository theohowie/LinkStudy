/// 优先排课引擎（纯函数领域层，不依赖 Flutter / 数据库 / 网络）。
///
/// 这是"论文算法设计"章节的参考实现，包含四个算法：
/// 1. 算法一：AHP 层次分析法计算课程优先系数 P_i；
/// 2. 算法二：可用时间片生成（粒度切分 + 不可用时间"与"运算排除）；
/// 3. 算法三：轻松/中等/高强度三档强度与时间片匹配规则；
/// 4. 算法四：贪心分配调度主流程（按 P_i 降序 + 强度适配匹配）。
library;

/// ===================== 算法一：AHP 优先系数 =====================

/// AHP 两两比较矩阵权重（2x2 几何平均法，无需解特征方程）。
///
/// 比较矩阵 A = [[1, a], [1/a, 1]]，a 表示"重要程度"相对"难度"的支配强度。
/// 2x2 一致矩阵的归一化特征向量可直接用几何平均法求得：
///   w_importance = sqrt(a) / (sqrt(a) + sqrt(1/a)) = a / (a + 1)
///   w_difficulty = 1 / (a + 1)
/// 当 a = 3 时 w_importance ≈ 0.75、w_difficulty ≈ 0.25。
({double difficulty, double importance}) ahpWeights({
  double importanceOverDifficulty = 3,
}) {
  assert(importanceOverDifficulty > 0, '比较强度必须为正');
  final a = importanceOverDifficulty;
  final wImportance = a / (a + 1);
  final wDifficulty = 1 / (a + 1);
  return (difficulty: wDifficulty, importance: wImportance);
}

/// min-max 归一化到 [0,1]；上下界相等时取中性值 0.5。
double _minMax(double x, double min, double max) =>
    max > min ? ((x - min) / (max - min)).clamp(0.0, 1.0) : 0.5;

/// 综合优先系数 P_i ∈ [0,1]。
///
/// 三个归一化因子加权：
///   P_i = (w_d·n_diff + w_i·n_imp + w_u·n_urg) / (w_d + w_i + w_u)
/// 其中 n_* 为集合内 min-max 归一化值；
/// w_u 为动态修正项：deadline 越近（n_urg 越大）权重越大（urgencyBase 放大），
/// 体现"时间偏差比"动态调整优先级的思路。
double priorityCoefficient({
  required double difficulty, // 1-9
  required double importance, // 1-9
  int? deadlineDays, // 距截止的天数；null = 无截止
  required double minDifficulty,
  required double maxDifficulty,
  required double minImportance,
  required double maxImportance,
  required double minUrgency,
  required double maxUrgency,
  double importanceOverDifficulty = 3,
  double urgencyBase = 0.2,
}) {
  final w = ahpWeights(importanceOverDifficulty: importanceOverDifficulty);
  final urgency = deadlineDays == null ? 0.0 : 1 / (deadlineDays + 1);
  final nDiff = _minMax(difficulty, minDifficulty, maxDifficulty);
  final nImp = _minMax(importance, minImportance, maxImportance);
  final nUrg = _minMax(urgency, minUrgency, maxUrgency);
  // 动态权重：截止越近放大（0.2 → 0.8）。
  final wUrgency = urgencyBase * (1 + 3 * nUrg);
  final total = w.difficulty + w.importance + wUrgency;
  return (w.difficulty * nDiff + w.importance * nImp + wUrgency * nUrg) / total;
}

/// ===================== 算法二：可用时间片生成 =====================

/// 把 [dayStart, dayEnd)（分钟）按 [sliceMinutes] 切分成时间片，
/// 用 blocked 不可用时间段做布尔"与"运算排除，返回按时间排序的可用片。
///
/// 例：8:00-12:00、粒度 30min、blocked 9:00-10:00 →
/// 可用 [8:00-8:30, 8:30-9:00, 10:00-10:30, ...]。
List<({int start, int end})> availableSlices({
  required int dayStart,
  required int dayEnd,
  required int sliceMinutes,
  required List<({int start, int end})> blocked,
}) {
  assert(sliceMinutes > 0);
  final sorted = [...blocked]..sort((a, b) => a.start.compareTo(b.start));
  final slices = <({int start, int end})>[];
  var cursor = dayStart;
  for (final b in sorted) {
    if (b.end <= cursor) continue; // 完全在已扫描区之前
    if (b.start > cursor) {
      // 空闲区 [cursor, b.start)：切块。
      for (var s = cursor; s + sliceMinutes <= b.start; s += sliceMinutes) {
        slices.add((start: s, end: s + sliceMinutes));
      }
    }
    cursor = b.end > cursor ? b.end : cursor;
    if (cursor >= dayEnd) break;
  }
  for (var s = cursor; s + sliceMinutes <= dayEnd; s += sliceMinutes) {
    slices.add((start: s, end: s + sliceMinutes));
  }
  return slices;
}

/// ===================== 算法三：强度档位与时间片匹配 =====================

/// 学习强度档位：不按"时长长短"划分，而是对应不同的认知负荷承受
/// 能力与时间分布规律（高强度=峰值时段连续块、中等=间隔重复、轻松=碎片填缝）。
enum IntensityLevel { light, medium, high }

/// 每门课的强度适配参数（可配置）。
class IntensityProfile {
  const IntensityProfile({
    required this.maxSessionMinutes, // 单次时间块时长上限 T_max
    required this.dailyCapMinutes, // 每日该强度总时长硬上限 D_max
    required this.chunkMinutes, // 单块期望时长（中等档拆块粒度）
    required this.intervalDays, // 间隔天数（中等档间隔重复，1 = 隔天）
  });

  final int maxSessionMinutes;
  final int dailyCapMinutes;
  final int chunkMinutes;
  final int intervalDays;

  static const light = IntensityProfile(
    maxSessionMinutes: 45,
    dailyCapMinutes: 180,
    chunkMinutes: 0, // 0 = 一次放满（填缝任务不拆块）
    intervalDays: 0,
  );
  static const medium = IntensityProfile(
    maxSessionMinutes: 60,
    dailyCapMinutes: 150,
    chunkMinutes: 30,
    intervalDays: 1,
  );
  static const high = IntensityProfile(
    maxSessionMinutes: 50,
    dailyCapMinutes: 90,
    chunkMinutes: 50,
    intervalDays: 0,
  );
}

/// ===================== 算法四：贪心分配调度 =====================

/// 参与排课的课程（已含 AHP 优先系数）。
class PriorityCourse {
  const PriorityCourse({
    required this.id,
    required this.title,
    required this.durationMinutes,
    required this.priority, // P_i ∈ [0,1]，由算法一计算
    required this.intensity,
  });

  final String id;
  final String title;
  final int durationMinutes;
  final double priority;
  final IntensityLevel intensity;
}

/// 一天内的一次放置。
typedef Placement = ({String courseId, int day, int start, int end});

/// 无法放置的课程。
typedef PlacementFailure = ({String courseId, String reason});

/// 调度结果。
class PriorityScheduleResult {
  const PriorityScheduleResult({
    required this.placements,
    required this.failures,
  });

  final List<Placement> placements;
  final List<PlacementFailure> failures;

  bool get allScheduled => failures.isEmpty;
}

/// 贪心分配调度器（算法四）。
///
/// 流程：
/// 1. 课程按优先系数 P_i 降序排序；
/// 2. 每天维护一个"可用区间"集合（由时间片合并，随分配逐步收缩）；
/// 3. 逐课按其强度档位匹配时间片：
///    - high：在专注峰值时段（peaks）内找连续块，单块 ≤ T_max、
///      每日累计 ≤ D_max，放不下时拆块到后续天；
///    - medium：按间隔重复规律（intervalDays）分散到多天，每天一块；
///    - light：碎片填缝，任意可用片，一次放满；
/// 4. 候选片不足时降级匹配（high 找不到峰值片 → 普通片；light 无片 → 失败）；
/// 5. 仍有课程放不下 → 记录失败原因（时间范围不足）。
class PriorityScheduler {
  const PriorityScheduler({
    this.importanceOverDifficulty = 3,
    this.urgencyBase = 0.2,
  });

  final double importanceOverDifficulty;
  final double urgencyBase;

  /// 调度入口。
  ///
  /// [courses] 待排课程（P_i 需已计算）；
  /// [horizonDays] 排课窗口天数；
  /// [dayStart]/[dayEnd] 每天可用时间范围（分钟）；
  /// [blockedByDay] 每天不可用时间段（下标 0 = 第 1 天）；
  /// [peaksByDay] 每天专注峰值时段（高强度档优先匹配）；
  /// [profiles] 三档强度配置（默认内置值）。
  PriorityScheduleResult run({
    required List<PriorityCourse> courses,
    required int horizonDays,
    required int dayStart,
    required int dayEnd,
    required List<List<({int start, int end})>> blockedByDay,
    List<List<({int start, int end})>>? peaksByDay,
    Map<IntensityLevel, IntensityProfile>? profiles,
    int sliceMinutes = 30,
  }) {
    final profileMap =
        profiles ?? {
          IntensityLevel.light: IntensityProfile.light,
          IntensityLevel.medium: IntensityProfile.medium,
          IntensityLevel.high: IntensityProfile.high,
        };
    final peaks =
        peaksByDay ??
        List.generate(
          horizonDays,
          (_) => const <({int start, int end})>[],
        );

    // 每天可用区间：先按时间片切分排除 blocked，再合并为区间。
    final avail = <int, List<({int start, int end})>>{
      for (var d = 0; d < horizonDays; d++)
        d: _mergeSlices(
          availableSlices(
            dayStart: dayStart,
            dayEnd: dayEnd,
            sliceMinutes: sliceMinutes,
            blocked: blockedByDay.length > d ? blockedByDay[d] : const [],
          ),
        ),
    };
    final dailyUsed = <int, Map<IntensityLevel, int>>{
      for (var d = 0; d < horizonDays; d++) d: {},
    };

    // 1. 按 P_i 降序。
    final sorted = [...courses]..sort((a, b) => b.priority.compareTo(a.priority));

    final placements = <Placement>[];
    final failures = <PlacementFailure>[];
    final lastDayByCourse = <String, int>{};

    for (final course in sorted) {
      final profile = profileMap[course.intensity]!;
      final placed = _placeCourse(
        course: course,
        profile: profile,
        horizonDays: horizonDays,
        avail: avail,
        dailyUsed: dailyUsed,
        peaks: peaks,
        lastDayByCourse: lastDayByCourse,
      );
      if (placed == null) {
        failures.add((
          courseId: course.id,
          reason: '《${course.title}》时长 ${course.durationMinutes} 分钟，'
              '时间窗口内无满足强度档位的可用时间',
        ));
        continue;
      }
      placements.addAll(placed);
    }

    placements.sort(
      (a, b) => a.day != b.day
          ? a.day.compareTo(b.day)
          : a.start.compareTo(b.start),
    );
    return PriorityScheduleResult(placements: placements, failures: failures);
  }

  /// 为一门课分配一个或多个块（返回已放置列表；放不下返回 null）。
  List<Placement>? _placeCourse({
    required PriorityCourse course,
    required IntensityProfile profile,
    required int horizonDays,
    required Map<int, List<({int start, int end})>> avail,
    required Map<int, Map<IntensityLevel, int>> dailyUsed,
    required List<List<({int start, int end})>> peaks,
    required Map<String, int> lastDayByCourse,
  }) {
    final placed = <Placement>[];
    var remaining = course.durationMinutes;

    // 中等档：间隔重复——起始日必须在上一放置日 + intervalDays 之后。
    var startDay = 0;
    final lastDay = lastDayByCourse[course.id];
    if (lastDay != null) {
      startDay = lastDay + profile.intervalDays + 1;
    }

    for (var day = startDay; day < horizonDays && remaining > 0; day++) {
      final used = dailyUsed[day]![course.intensity] ?? 0;
      if (used >= profile.dailyCapMinutes) continue; // D_max 硬上限
      final need = profile.chunkMinutes > 0
          ? _min(profile.chunkMinutes, remaining)
          : remaining;
      final capped = _min(need, profile.maxSessionMinutes); // T_max
      final headroom = profile.dailyCapMinutes - used;

      // 高强度优先在峰值时段内找；找不到降级到普通可用片。
      final peak = peaks.length > day ? peaks[day] : const <({int start, int end})>[];
      var block = _takeBlock(
        avail[day]!,
        peak.isNotEmpty ? peak : null,
        _min(capped, headroom),
      );
      if (block == null && peak.isNotEmpty) {
        block = _takeBlock(avail[day]!, null, _min(capped, headroom));
      }
      if (block == null) continue;

      placed.add((
        courseId: course.id,
        day: day,
        start: block.start,
        end: block.end,
      ));
      remaining -= block.end - block.start;
      lastDayByCourse[course.id] = day;
      dailyUsed[day]![course.intensity] = used + (block.end - block.start);

      // 间隔重复：下一块必须隔 intervalDays 天后再放（间隔学习效应）。
      if (profile.intervalDays > 0 && remaining > 0) {
        day += profile.intervalDays;
      }
    }

    if (remaining > 0) return null;
    return placed;
  }

  /// 从 [avail] 中取一块连续区间：优先与 [peaks] 交集匹配，
  /// 块长尽量贴近 [need]；取到后从可用集合中移除。
  ({int start, int end})? _takeBlock(
    List<({int start, int end})> avail,
    List<({int start, int end})>? peaks,
    int need,
  ) {
    if (need <= 0) return null;
    // 候选源：peaks 提供的区间或全部可用区间。
    final sources = peaks != null && peaks.isNotEmpty ? peaks : avail;
    for (final seg in sources) {
      final fit = _bestFitIn(seg, need);
      if (fit == null) continue;
      _removeRange(avail, fit);
      return fit;
    }
    // peaks 内没有足够大的块 → 在全部可用区间里找。
    if (peaks != null && peaks.isNotEmpty) {
      for (final seg in avail) {
        final fit = _bestFitIn(seg, need);
        if (fit == null) continue;
        _removeRange(avail, fit);
        return fit;
      }
    }
    return null;
  }

  /// 在单个区间内找长度 ≥ need 的连续子区间（起始尽量早）。
  ({int start, int end})? _bestFitIn(
    ({int start, int end}) seg,
    int need,
  ) {
    if (seg.end - seg.start < need) return null;
    return (start: seg.start, end: seg.start + need);
  }

  /// 从可用区间集合中移除 [range]，可能切分或删除。
  void _removeRange(
    List<({int start, int end})> avail,
    ({int start, int end}) range,
  ) {
    for (var i = 0; i < avail.length; i++) {
      final seg = avail[i];
      if (range.end <= seg.start || range.start >= seg.end) continue;
      if (range.start <= seg.start && range.end >= seg.end) {
        avail.removeAt(i);
        i--;
      } else if (range.start <= seg.start) {
        avail[i] = (start: range.end, end: seg.end);
      } else if (range.end >= seg.end) {
        avail[i] = (start: seg.start, end: range.start);
      } else {
        final right = (start: range.end, end: seg.end);
        avail[i] = (start: seg.start, end: range.start);
        avail.insert(i + 1, right);
      }
      return;
    }
  }

  /// 把时间片列表合并为区间（相邻片合并）。
  List<({int start, int end})> _mergeSlices(
    List<({int start, int end})> slices,
  ) {
    final merged = <({int start, int end})>[];
    for (final s in slices) {
      if (merged.isNotEmpty && s.start == merged.last.end) {
        merged[merged.length - 1] = (start: merged.last.start, end: s.end);
      } else {
        merged.add(s);
      }
    }
    return merged;
  }

  static int _min(int a, int b) => a < b ? a : b;
}
