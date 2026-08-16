import 'package:flutter/foundation.dart';

import '../models/general_event.dart';
import '../models/general_schedule.dart';
import '../providers/timetable_provider.dart';
import 'link_course.dart';

/// LinkStudy 课表桥接：把排课槽位同步为通用日程中"LinkStudy 课表"日历的单次事件，
/// 使课程直接显示在首页日程网格（时间线/月视图）中。
///
/// 悬浮窗采集的课程是一次性安排：事件**不重复**，锚定到排课的具体日期
/// （旧数据槽位缺失日期时回退到本周该 weekday）。
///
/// 同步时机：启动后、课程/槽位变化时调用 [sync]。
class LinkStudyGridSync {
  LinkStudyGridSync({required this.provider, required this.store});

  final TimetableProvider provider;
  final LinkCourseStore store;

  static const scheduleName = 'LinkStudy 课表';

  /// 课程网格事件 id 前缀（公开，供首页识别可拖拽课程事件）。
  static const eventIdPrefix = 'ls_';

  /// 把当前槽位同步到通用日程网格（幂等：事件 id 稳定，重复调用覆盖）。
  Future<void> sync() async {
    if (!provider.isLoaded) return;

    // 1. 按名字定位 LinkStudy 课表日历；清理历史重复项（早期版本按固定 id 查找失败产生的空日历）。
    var schedules = provider.generalSchedules
        .where((s) => s.name == scheduleName)
        .toList();
    if (schedules.length > 1) {
      for (final extra in schedules.skip(1)) {
        await provider.deleteGeneralSchedule(extra.id);
      }
      schedules = provider.generalSchedules
          .where((s) => s.name == scheduleName)
          .toList();
    }
    var schedule = schedules.isEmpty ? null : schedules.first;
    if (schedule == null) {
      await provider.addGeneralSchedule(
        name: scheduleName,
        colorValue: generalCalendarColorSlot2Value,
      );
      schedule = provider.generalSchedules
          .where((s) => s.name == scheduleName)
          .firstOrNull;
      if (schedule == null) return;
    }

    // 2. 重建事件：保留用户自己的事件 + 替换 LinkStudy 事件。
    final today = DateTime.now();
    final keptEvents = schedule.events
        .where((e) => !e.id.startsWith(eventIdPrefix))
        .toList();
    final linkEvents = <GeneralEvent>[
      for (final slot in store.slots)
        if (store.courseById(slot.courseId) case final course?)
          buildGridEvent(course, slot, calendarId: schedule.id, today: today),
    ];
    debugPrint(
      '[linkstudy] grid sync: slots=${store.slots.length} events=${linkEvents.length} schedule=${schedule.id}',
    );
    await provider.updateGeneralSchedule(
      schedule.copyWith(events: [...keptEvents, ...linkEvents]),
    );
  }
}

/// 网格事件的锚定日期：优先用排课日期（epochDay）；旧数据无日期时回退到本周该 weekday。
DateTime gridEventAnchor(ScheduleSlot slot, DateTime today) {
  final day = slot.epochDay;
  if (day != null) return localDateFromEpochDay(day);
  // 锚定到本周该 weekday 的日期（slot.weekday 为未来时自动顺延到本周内）。
  return today.subtract(Duration(days: today.weekday - slot.weekday));
}

/// 构建课程对应的网格事件。
///
/// 悬浮窗采集的课程默认是单次安排，因此**不设置重复规则**（recurrence=none），
/// 事件只出现在 [gridEventAnchor] 锚定的那一天。
GeneralEvent buildGridEvent(
  LinkCourse course,
  ScheduleSlot slot, {
  required String calendarId,
  DateTime? today,
}) {
  final anchor = gridEventAnchor(slot, today ?? DateTime.now());
  final start = DateTime(
    anchor.year,
    anchor.month,
    anchor.day,
    slot.startMinute ~/ 60,
    slot.startMinute % 60,
  );
  final end = DateTime(
    anchor.year,
    anchor.month,
    anchor.day,
    slot.endMinute ~/ 60,
    slot.endMinute % 60,
  );
  return GeneralEvent(
    id: '${LinkStudyGridSync.eventIdPrefix}${course.id}',
    calendarId: calendarId,
    title: course.title,
    startDateTimeIso: start.toIso8601String(),
    endDateTimeIso: end.toIso8601String(),
    // 课程颜色（AI 建议）在网格展示时使用。
    colorValue: slot.colorValue,
  );
}
