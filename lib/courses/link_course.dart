import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'scheduler_engine.dart';

/// 课程优先级。
enum CoursePriority { high, medium, low }

/// 每日一个可用时段（如 19:00-22:00）。
class AvailabilitySlot {
  final int startMinute;
  final int endMinute;

  const AvailabilitySlot({required this.startMinute, required this.endMinute});

  int get durationMinutes => endMinute - startMinute;

  Map<String, dynamic> toJson() =>
      {'startMinute': startMinute, 'endMinute': endMinute};

  factory AvailabilitySlot.fromJson(Map<String, dynamic> json) =>
      AvailabilitySlot(
        startMinute: (json['startMinute'] as num?)?.toInt() ?? 19 * 60,
        endMinute: (json['endMinute'] as num?)?.toInt() ?? 22 * 60,
      );
}

/// 日期 → epochDay（自 1970-01-01 UTC 起的天数，仅日期部分；与 deadlineDay 同约定）。
int epochDayOf(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day)
        .difference(DateTime.utc(1970, 1, 1))
        .inDays;

/// epochDay → 本地日期（仅日期部分，时间归零）。
DateTime localDateFromEpochDay(int day) {
  final utc = DateTime.utc(1970, 1, 1).add(Duration(days: day));
  return DateTime(utc.year, utc.month, utc.day);
}

/// 排课槽位：课程在课表中的位置（排课日期 + 星期几 + 起止分钟）。
class ScheduleSlot {
  final String courseId;
  final int? epochDay; // 排课的具体日期；旧数据可能缺失，网格同步时回退到本周。
  final int weekday; // 1=周一 … 7=周日
  final int startMinute;
  final int endMinute;

  const ScheduleSlot({
    required this.courseId,
    this.epochDay,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
  });

  Map<String, dynamic> toJson() => {
        'courseId': courseId,
        'day': epochDay,
        'weekday': weekday,
        'startMinute': startMinute,
        'endMinute': endMinute,
      };

  factory ScheduleSlot.fromJson(Map<String, dynamic> json) => ScheduleSlot(
        courseId: json['courseId'] as String,
        epochDay: (json['day'] as num?)?.toInt(),
        weekday: (json['weekday'] as num).toInt(),
        startMinute: (json['startMinute'] as num).toInt(),
        endMinute: (json['endMinute'] as num).toInt(),
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
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
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
          _courses = _list(data['courses'])
              .map((e) => LinkCourse.fromJson(e as Map<String, dynamic>))
              .toList();
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

  /// 添加课程并自动排课（悬浮窗草稿/手动录入的统一入口）。
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
    await schedulePending();
    notifyListeners();
    await _persist();
    return course;
  }

  /// 对全部待排课程执行自动排课（覆盖式重建槽位，保留手动锁定槽位）。
  Future<SchedulingResult> schedulePending() async {
    final pending = _courses
        .where((c) => !_slots.any((s) => s.courseId == c.id))
        .toList();
    if (pending.isEmpty) {
      return const SchedulingResult(placements: [], failures: []);
    }
    // 已占用区间（现有槽位 + 排课过程中新增），用于冲突检测。
    final occupied = <int, List<({int start, int end})>>{};
    for (final s in _slots) {
      (occupied[s.weekday] ??= []).add((start: s.startMinute, end: s.endMinute));
    }
    final result = scheduleCourses(
      pending: pending,
      availabilityByWeekday: _availability,
      occupied: occupied,
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

  Future<File> _resolveFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<String?> _readIfExists(File file) async {
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> _persist() async {
    try {
      final file = await _resolveFile();
      final backup = File('${file.path}$_backupSuffix');
      final content = jsonEncode({
        'courses': _courses.map((c) => c.toJson()).toList(),
        'slots': _slots.map((s) => s.toJson()).toList(),
        'availability': [
          for (final day in _availability)
            day.map((a) => a.toJson()).toList(),
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

  static List<dynamic> _list(Object? value) =>
      value is List ? value : const [];

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

  static String _newId() =>
      'course_${DateTime.now().microsecondsSinceEpoch}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
