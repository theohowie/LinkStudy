import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'scheduler_engine.dart';

/// 课程优先级。
enum CoursePriority { high, medium, low }

/// AI 建议的单门课具体时间安排（AI 输出的 startDay/startTime/endTime）。
class AiPlacement {
  const AiPlacement({
    required this.courseId,
    required this.dayOffset, // 0=排课起始日（明天/今天），对应 startDay-1
    required this.startMinute,
    required this.endMinute,
  });

  final String courseId;
  final int dayOffset;
  final int startMinute;
  final int endMinute;

  int get durationMinutes => endMinute - startMinute;
}

/// 每日一个可用时段（如 19:00-22:00）。
class AvailabilitySlot {
  final int startMinute;
  final int endMinute;

  const AvailabilitySlot({required this.startMinute, required this.endMinute});

  int get durationMinutes => endMinute - startMinute;

  Map<String, dynamic> toJson() => {
    'startMinute': startMinute,
    'endMinute': endMinute,
  };

  factory AvailabilitySlot.fromJson(Map<String, dynamic> json) =>
      AvailabilitySlot(
        startMinute: (json['startMinute'] as num?)?.toInt() ?? 19 * 60,
        endMinute: (json['endMinute'] as num?)?.toInt() ?? 22 * 60,
      );
}

/// 日期 → epochDay（自 1970-01-01 UTC 起的天数，仅日期部分；与 deadlineDay 同约定）。
int epochDayOf(DateTime date) => DateTime.utc(
  date.year,
  date.month,
  date.day,
).difference(DateTime.utc(1970, 1, 1)).inDays;

/// epochDay → 本地日期（仅日期部分，时间归零）。
DateTime localDateFromEpochDay(int day) {
  final utc = DateTime.utc(1970, 1, 1).add(Duration(days: day));
  return DateTime(utc.year, utc.month, utc.day);
}

/// 从通用显示设置（开始/午休/结束时间，分钟级）构建每天的学习可用时段（7 天相同）。
/// 时段 = [开始, 午休开始) + [午休结束, 结束)；午休无效时退化为 [开始, 结束)；
/// 全部无效时回退默认 19:00-22:00。
List<List<AvailabilitySlot>> availabilityFromDayWindow({
  required int startMinute,
  required int lunchStartMinute,
  required int lunchEndMinute,
  required int endMinute,
}) {
  final morningStart = startMinute.clamp(0, 24 * 60 - 1);
  final lunchStart = lunchStartMinute.clamp(0, 24 * 60);
  final lunchEnd = lunchEndMinute.clamp(0, 24 * 60);
  final eveningEnd = endMinute.clamp(1, 24 * 60);

  final slots = <AvailabilitySlot>[];
  if (lunchStart > morningStart) {
    slots.add(
      AvailabilitySlot(startMinute: morningStart, endMinute: lunchStart),
    );
  }
  if (eveningEnd > lunchEnd) {
    slots.add(AvailabilitySlot(startMinute: lunchEnd, endMinute: eveningEnd));
  }
  if (slots.isEmpty && eveningEnd > morningStart) {
    slots.add(
      AvailabilitySlot(startMinute: morningStart, endMinute: eveningEnd),
    );
  }
  return List.generate(
    7,
    (_) => slots.isEmpty ? defaultAvailability() : List.unmodifiable(slots),
  );
}

/// 排课槽位：课程在课表中的位置（排课日期 + 星期几 + 起止分钟）。
class ScheduleSlot {
  final String courseId;
  final int? epochDay; // 排课的具体日期；旧数据可能缺失，网格同步时回退到本周。
  final int weekday; // 1=周一 … 7=周日
  final int startMinute;
  final int endMinute;
  final int? colorValue; // 课程在网格展示的颜色（ARGB，来自 AI 建议或本地分配）。

  const ScheduleSlot({
    required this.courseId,
    this.epochDay,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    this.colorValue,
  });

  Map<String, dynamic> toJson() => {
    'courseId': courseId,
    'day': epochDay,
    'weekday': weekday,
    'startMinute': startMinute,
    'endMinute': endMinute,
    'color': colorValue,
  };

  factory ScheduleSlot.fromJson(Map<String, dynamic> json) => ScheduleSlot(
    courseId: json['courseId'] as String,
    epochDay: (json['day'] as num?)?.toInt(),
    weekday: (json['weekday'] as num).toInt(),
    startMinute: (json['startMinute'] as num).toInt(),
    endMinute: (json['endMinute'] as num).toInt(),
    colorValue: (json['color'] as num?)?.toInt(),
  );
}

/// 一条网课课程（悬浮窗采集入库）。
class LinkCourse {
  final String id;
  final String url;
  final String title;
  final int durationMinutes;
  final DateTime createdAt;
  final int? deadlineDay; // 可选：截止日期（epochDay，仅日期）
  final CoursePriority priority;

  const LinkCourse({
    required this.id,
    required this.url,
    required this.title,
    required this.durationMinutes,
    required this.createdAt,
    this.deadlineDay,
    this.priority = CoursePriority.medium,
  });

  LinkCourse copyWith({
    String? title,
    int? durationMinutes,
    int? Function()? deadlineDay,
    CoursePriority? priority,
  }) {
    return LinkCourse(
      id: id,
      url: url,
      title: title ?? this.title,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      createdAt: createdAt,
      deadlineDay: deadlineDay != null ? deadlineDay() : this.deadlineDay,
      priority: priority ?? this.priority,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'title': title,
    'durationMinutes': durationMinutes,
    'createdAt': createdAt.toIso8601String(),
    'deadlineDay': deadlineDay,
    'priority': priority.name,
  };

  factory LinkCourse.fromJson(Map<String, dynamic> json) => LinkCourse(
    id: json['id'] as String,
    url: json['url'] as String? ?? '',
    title: json['title'] as String? ?? '',
    durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 0,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    deadlineDay: (json['deadlineDay'] as num?)?.toInt(),
    priority: CoursePriority.values.firstWhere(
      (p) => p.name == json['priority'],
      orElse: () => CoursePriority.medium,
    ),
  );
}

/// 课程存储（本地 JSON 文件，原子写 + .bak 备份）。
/// ChangeNotifier 便于后续 UI 监听变化。
class LinkCourseStore extends ChangeNotifier {
  LinkCourseStore._();

  static final LinkCourseStore instance = LinkCourseStore._();

  static const _fileName = 'linkstudy_courses.json';
  static const _backupSuffix = '.bak';

  List<LinkCourse> _courses = [];
  List<ScheduleSlot> _slots = [];
  List<List<AvailabilitySlot>> _availability = List.generate(
    7,
    (_) => defaultAvailability(),
  );
  bool _loaded = false;

  List<LinkCourse> get courses => List.unmodifiable(_courses);
  List<ScheduleSlot> get slots => List.unmodifiable(_slots);
  List<List<AvailabilitySlot>> get availabilityByWeekday => _availability;
  bool get isLoaded => _loaded;

  /// 启动时加载（main 调用一次）。
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final file = await _resolveFile();
      final backup = File('${file.path}$_backupSuffix');
      var content = await _readIfExists(file);
      if (content == null && await backup.exists()) {
        content = await backup.readAsString();
      }
      if (content != null && content.trim().isNotEmpty) {
        final decoded = jsonDecode(content);
        if (decoded is List) {
          // 兼容旧版格式：顶层为课程列表。
          _courses = decoded
              .map((e) => LinkCourse.fromJson(e as Map<String, dynamic>))
              .toList();
        } else if (decoded is Map<String, dynamic>) {
          final data = decoded;
          _courses = _list(
            data['courses'],
          ).map((e) => LinkCourse.fromJson(e as Map<String, dynamic>)).toList();
          _slots = _list(data['slots'])
              .map((e) => ScheduleSlot.fromJson(e as Map<String, dynamic>))
              .toList();
          _availability = _decodeAvailability(data['availability']);
        }
      }
    } catch (e, st) {
      debugPrint('LinkCourseStore load failed: $e\n$st');
      _courses = [];
    }
    _loaded = true;
    notifyListeners();
  }

  /// 添加课程（悬浮窗草稿/手动录入的统一入口）。
  /// 课程先进"未排课池"（不自动排课），由用户在排课流程中统一安排。
  Future<LinkCourse> addCourse({
    required String url,
    required String title,
    required int durationMinutes,
    int? deadlineDay,
    CoursePriority priority = CoursePriority.medium,
  }) async {
    final course = LinkCourse(
      id: _newId(),
      url: url.trim(),
      title: title.trim(),
      durationMinutes: durationMinutes,
      createdAt: DateTime.now(),
      deadlineDay: deadlineDay,
      priority: priority,
    );
    _courses = [..._courses, course];
    notifyListeners();
    await _persist();
    return course;
  }

  /// 未排课数量（暂无槽位的课程数）。
  int get pendingCount =>
      _courses.where((c) => !_slots.any((s) => s.courseId == c.id)).length;

  /// 按 AI 顺序排课：对 [courseIds]（本次勾选的课程）移除旧槽位，
  /// 按 [ordered]（可为空=默认贪心顺序）在 [days] 天窗口内落位；
  /// [availabilityByWeekday] 为每天可用时段（来自通用显示设置）。
  /// [startFromNow] true=从现在开始（裁剪今天已过时段）；false=从指定日期开始（今天不排）。
  /// [anchorDate] 可选：排课起始日锚点（startFromNow=false 时使用；null 则默认明天）。
  /// [courseColors] 每门课在网格展示的颜色（courseId → ARGB，来自 AI 建议）。
  /// [aiPlacements] AI 给出的具体时间安排（技能文件包输出契约）：
  /// 优先采用（校验在窗口内、时长匹配、不重叠）；校验失败的课程回退本地贪心落位。
  Future<SchedulingResult> scheduleWithOrder({
    required List<String> courseIds,
    required List<OrderedCourse> ordered,
    required int days,
    required List<List<AvailabilitySlot>> availabilityByWeekday,
    bool startFromNow = true,
    DateTime? anchorDate,
    Map<String, int>? courseColors,
    List<AiPlacement> aiPlacements = const [],
  }) async {
    final ids = courseIds.toSet();
    final pending = _courses.where((c) => ids.contains(c.id)).toList();
    // 移除这些课程的旧槽位（重新排）。
    _slots = _slots.where((s) => !ids.contains(s.courseId)).toList();
    if (pending.isEmpty) {
      notifyListeners();
      await _persist();
      return const SchedulingResult(placements: [], failures: []);
    }
    final today = startFromNow
        ? DateTime.now()
        : (anchorDate ?? DateTime.now().add(const Duration(days: 1)));

    final placements = <SchedulePlacement>[];
    final failures = <({String courseId, String reason})>[];
    final colors = _assignColors(
      courseIds: ids,
      aiColors: courseColors ?? const {},
    );

    // 阶段 A：优先采用 AI 给出的具体时间（校验合法性）。
    // 支持"课程内插入休息"：同一门课可拆为多段（同 courseId 多条 placement），
    // 段间空隙即为休息；校验所有段的总时长不超过课程时长、各段不重叠且在窗口内。
    final adoptedTotal = <String, int>{}; // courseId → 已采用的总时长(分钟)
    if (aiPlacements.isNotEmpty) {
      for (final p in aiPlacements) {
        final course = pending.where((c) => c.id == p.courseId).firstOrNull;
        if (course == null) continue;
        // 校验：窗口内天数、该课程累计时长不超、不与已采用槽位重叠。
        if (p.dayOffset < 0 || p.dayOffset >= days.clamp(1, 30)) continue;
        final usedTotal = adoptedTotal[p.courseId] ?? 0;
        if (usedTotal + p.durationMinutes > course.durationMinutes) continue;
        final day = epochDayOf(today) + p.dayOffset;
        final weekday = localDateFromEpochDay(day).weekday;
        final overlaps = placements.any(
          (q) => q.day == day && p.startMinute < q.end && p.endMinute > q.start,
        );
        if (overlaps) continue;
        // 校验：落在当天可用时段内。
        final avail = availabilityByWeekday.length >= weekday
            ? availabilityByWeekday[weekday - 1]
            : const <AvailabilitySlot>[];
        final inWindow = avail.any(
          (seg) =>
              p.startMinute >= seg.startMinute && p.endMinute <= seg.endMinute,
        );
        if (!inWindow) continue;
        adoptedTotal[p.courseId] = usedTotal + p.durationMinutes;
        placements.add((
          courseId: p.courseId,
          day: day,
          weekday: weekday,
          start: p.startMinute,
          end: p.endMinute,
        ));
      }
      // 只有"已排满整门课"的课程才算采用（避免只用了 AI 部分片段却被当整门课跳过）。
      final adopted = <String>{
        for (final c in pending)
          if ((adoptedTotal[c.id] ?? 0) >= c.durationMinutes) c.id,
      };
      // 阶段 B：未完全采用 AI 时间的课程按顺序贪心落位（补足剩余时长或整体重排）。
      // 注意：occupied 必须包含阶段 A 已采用的槽位，否则本地落位会与 AI 落位重叠。
      final pendingRest = pending
          .where((c) => !adopted.contains(c.id))
          .toList();
      if (pendingRest.isNotEmpty) {
        final occupiedMap = _occupiedFromSlots(_slots);
        for (final p in placements) {
          (occupiedMap[p.weekday] ??= []).add((start: p.start, end: p.end));
        }
        final result = scheduleCourses(
          pending: pendingRest,
          availabilityByWeekday: availabilityByWeekday,
          occupied: occupiedMap,
          today: today,
          ordered: ordered.isEmpty ? null : ordered,
          horizonDays: days.clamp(1, 30),
          startFromNow: startFromNow,
        );
        placements.addAll(result.placements);
        failures.addAll(result.failures);
      }
    } else {
      // 无 AI 具体时间 → 全部按顺序贪心落位。
      final occupiedMap = _occupiedFromSlots(_slots);
      final result = scheduleCourses(
        pending: pending,
        availabilityByWeekday: availabilityByWeekday,
        occupied: occupiedMap,
        today: today,
        ordered: ordered.isEmpty ? null : ordered,
        horizonDays: days.clamp(1, 30),
        startFromNow: startFromNow,
      );
      placements.addAll(result.placements);
      failures.addAll(result.failures);
    }

    final added = [
      for (final p in placements)
        ScheduleSlot(
          courseId: p.courseId,
          epochDay: p.day,
          weekday: p.weekday,
          startMinute: p.start,
          endMinute: p.end,
          colorValue: colors[p.courseId],
        ),
    ];
    _slots = [..._slots, ...added];
    notifyListeners();
    await _persist();
    return SchedulingResult(placements: placements, failures: failures);
  }

  /// 课程颜色兜底：AI 给了颜色的课程用 AI 色；其余按固定调色板顺序分配，
  /// 保证每门课颜色不同（修复"颜色又一样"问题）。
  static const _palette = [
    0xFF4D6BFE, // 蓝
    0xFF22A06B, // 绿
    0xFFE8590C, // 橙
    0xFF9C36B5, // 紫
    0xFFE03131, // 红
    0xFF0CA678, // 青绿
    0xFFF08C00, // 琥珀
    0xFF1971C2, // 深蓝
    0xFFE64980, // 玫红
    0xFF2F9E44, // 草绿
  ];

  static Map<String, int> _assignColors({
    required Set<String> courseIds,
    required Map<String, int> aiColors,
  }) {
    final result = <String, int>{};
    final orderedIds = courseIds.toList();
    var paletteIndex = 0;
    final used = <int>{};
    for (final id in orderedIds) {
      final ai = aiColors[id];
      if (ai != null && !used.contains(ai)) {
        result[id] = ai;
        used.add(ai);
        continue;
      }
      // AI 色缺失或重复 → 从调色板取下一个未用色。
      while (used.contains(_palette[paletteIndex % _palette.length])) {
        paletteIndex++;
      }
      result[id] = _palette[paletteIndex % _palette.length];
      used.add(result[id]!);
      paletteIndex++;
    }
    return result;
  }

  /// 对全部待排课程执行自动排课（贪心兜底；AI 不可用时的回退路径）。
  Future<SchedulingResult> schedulePending() async {
    final pending = _courses
        .where((c) => !_slots.any((s) => s.courseId == c.id))
        .toList();
    if (pending.isEmpty) {
      return const SchedulingResult(placements: [], failures: []);
    }
    final result = scheduleCourses(
      pending: pending,
      availabilityByWeekday: _availability,
      occupied: _occupiedFromSlots(_slots),
      today: DateTime.now(),
    );
    final added = [
      for (final p in result.placements)
        ScheduleSlot(
          courseId: p.courseId,
          epochDay: p.day,
          weekday: p.weekday,
          startMinute: p.start,
          endMinute: p.end,
        ),
    ];
    _slots = [..._slots, ...added];
    notifyListeners();
    await _persist();
    return result;
  }

  static Map<int, List<({int start, int end})>> _occupiedFromSlots(
    List<ScheduleSlot> slots,
  ) {
    final occupied = <int, List<({int start, int end})>>{};
    for (final s in slots) {
      (occupied[s.weekday] ??= []).add((
        start: s.startMinute,
        end: s.endMinute,
      ));
    }
    return occupied;
  }

  /// 某天的槽位（按开始时间排序），附课程。
  List<({ScheduleSlot slot, LinkCourse course})> slotsOnDay(int weekday) {
    final result = <({ScheduleSlot slot, LinkCourse course})>[];
    for (final slot in _slots.where((s) => s.weekday == weekday)) {
      final course = _courses.where((c) => c.id == slot.courseId).firstOrNull;
      if (course != null) {
        result.add((slot: slot, course: course));
      }
    }
    result.sort((a, b) => a.slot.startMinute.compareTo(b.slot.startMinute));
    return result;
  }

  Future<void> deleteCourse(String id) async {
    _courses = _courses.where((c) => c.id != id).toList();
    _slots = _slots.where((s) => s.courseId != id).toList();
    notifyListeners();
    await _persist();
  }

  /// 移除课程的槽位（网格删除联动：删除"LinkStudy 课表"里的课程日程时，
  /// 课程回到未排课池，网格同步不再重建该事件）。
  Future<void> removeSlotForCourse(String courseId) async {
    final next = _slots.where((s) => s.courseId != courseId).toList();
    if (next.length == _slots.length) return;
    _slots = next;
    notifyListeners();
    await _persist();
  }

  /// 清空指定课程的槽位（一键重排用：课程回到未排课池，重新 AI 排课）。
  Future<void> clearSlotsForCourses(Iterable<String> courseIds) async {
    final ids = courseIds.toSet();
    final next = _slots.where((s) => !ids.contains(s.courseId)).toList();
    if (next.length == _slots.length) return;
    _slots = next;
    notifyListeners();
    await _persist();
  }

  /// 手动调整课程槽位的时间（网格长按拖拽联动）：
  /// 以 [anchorSlotIndex]（默认 0，即最早一段）为锚点，把整门课的所有段
  /// 一起平移到新日期/新开始时间，保持各段之间的相对间隔与各自时长不变。
  ///
  /// 例如数据结构被拆成 4 段，拖动第 1 段 → 4 段整体平移，
  /// 段间休息间隔保持不变，不会重叠。
  Future<void> moveSlot(
    String courseId, {
    required int epochDay,
    required int weekday,
    required int startMinute,
    int anchorSlotIndex = 0,
  }) async {
    final slots = _slots.where((s) => s.courseId == courseId).toList()
      ..sort((a, b) {
        final da = a.epochDay ?? 0;
        final db = b.epochDay ?? 0;
        return da != db
            ? da.compareTo(db)
            : a.startMinute.compareTo(b.startMinute);
      });
    if (slots.isEmpty) return;
    final anchor = slots[anchorSlotIndex.clamp(0, slots.length - 1)];
    // 锚点原始起始分钟与日期。
    final anchorDay = anchor.epochDay ?? 0;
    final anchorStart = anchor.startMinute;
    // 目标锚点分钟偏移（相对新日期 0 点）与目标日期的分钟偏移。
    final targetAnchorMinute = startMinute; // 新锚点开始分钟(当日)
    final dayDelta = epochDay - anchorDay;
    final minuteDelta = targetAnchorMinute - anchorStart;

    final next = <ScheduleSlot>[];
    var changed = false;
    for (final s in _slots) {
      if (s.courseId != courseId) {
        next.add(s);
        continue;
      }
      final oldDay = s.epochDay ?? 0;
      final newDay = oldDay + dayDelta;
      final newStart = s.startMinute + minuteDelta;
      final newEnd = s.endMinute + minuteDelta;
      if (newStart < 0 || newEnd > 24 * 60) continue; // 越界则跳过该段
      final date = localDateFromEpochDay(newDay);
      next.add(
        ScheduleSlot(
          courseId: s.courseId,
          epochDay: newDay,
          weekday: date.weekday,
          startMinute: newStart,
          endMinute: newEnd,
          colorValue: s.colorValue,
        ),
      );
      changed = true;
    }
    if (!changed) return;
    _slots = next;
    notifyListeners();
    await _persist();
  }

  LinkCourse? courseById(String id) =>
      _courses.where((c) => c.id == id).firstOrNull;

  /// 仅测试用：清空内存中的课程与槽位（不落盘）。
  @visibleForTesting
  void debugClear() {
    _courses = [];
    _slots = [];
    _loaded = true;
    notifyListeners();
  }

  /// 仅测试用：直接注入槽位（构造多段课程场景）。
  @visibleForTesting
  void injectSlotsForTest(List<ScheduleSlot> slots) {
    _slots = [...slots];
    notifyListeners();
  }

  /// 替换全部槽位（撤销/重做课程移动用），并持久化。
  Future<void> replaceSlots(List<ScheduleSlot> slots) async {
    _slots = [...slots];
    notifyListeners();
    await _persist();
  }

  /// 仅测试用：跳过持久化（widget 测试的 FakeAsync 环境无法完成真实文件 I/O）。
  @visibleForTesting
  bool debugSkipPersist = false;

  Future<File> _resolveFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<String?> _readIfExists(File file) async {
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> _persist() async {
    if (debugSkipPersist) return;
    try {
      final file = await _resolveFile();
      final backup = File('${file.path}$_backupSuffix');
      final content = jsonEncode({
        'courses': _courses.map((c) => c.toJson()).toList(),
        'slots': _slots.map((s) => s.toJson()).toList(),
        'availability': [
          for (final day in _availability) day.map((a) => a.toJson()).toList(),
        ],
      });
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(content);
      if (await file.exists()) {
        if (await backup.exists()) {
          await backup.delete();
        }
        await file.rename('${file.path}$_backupSuffix');
      }
      await tmp.rename(file.path);
    } catch (e, st) {
      debugPrint('LinkCourseStore persist failed: $e\n$st');
    }
  }

  static List<dynamic> _list(Object? value) => value is List ? value : const [];

  static List<List<AvailabilitySlot>> _decodeAvailability(Object? value) {
    if (value is! List || value.length != 7) {
      return List.generate(7, (_) => defaultAvailability());
    }
    return [
      for (final day in value)
        if (day is List)
          day
              .whereType<Map<String, dynamic>>()
              .map(AvailabilitySlot.fromJson)
              .toList()
        else
          <AvailabilitySlot>[],
    ];
  }

  static int _idSeq = 0;

  /// 生成唯一课程 id：微秒时间戳 + 进程内递增序号，防止同一微秒内快速创建时撞 id。
  static String _newId() {
    _idSeq++;
    return 'course_${DateTime.now().microsecondsSinceEpoch}_$_idSeq';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
