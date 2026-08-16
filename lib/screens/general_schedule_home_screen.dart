import '../models/general_models.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lunar/lunar.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../courses/ai_schedule_runner.dart';
import '../courses/link_course.dart';
import '../courses/link_study_grid_sync.dart';
import '../providers/timetable_provider.dart';
import '../utils/general_schedule_colors.dart';
import '../widgets/app_modal_sheet.dart';
import '../widgets/ai_schedule_setup_sheet.dart';
import '../widgets/course_pending_sheet.dart';
import '../widgets/share_schedule_sheet.dart';
import '../widgets/timeline_precision_sheet.dart';
import '../widgets/expressive_empty_state.dart';
import '../widgets/expressive_dialog.dart';
import '../widgets/expressive_motion.dart';
import '../widgets/general_event_details_sheet.dart';
import '../widgets/general_event_editor_sheet.dart';
import '../widgets/ai_schedule_progress_sheet.dart';
import 'settings_page.dart';

part 'general_schedule_list_view.dart';
part 'general_schedule_reminder_strip.dart';
part 'general_schedule_timeline_view.dart';
part 'general_schedule_timeline_components.dart';
part 'general_schedule_calendar_manager.dart';
part 'general_schedule_month_view.dart';

class GeneralScheduleHomeScreen extends StatefulWidget {
  const GeneralScheduleHomeScreen({super.key});

  @override
  State<GeneralScheduleHomeScreen> createState() =>
      _GeneralScheduleHomeScreenState();
}

class _GeneralScheduleHomeScreenState extends State<GeneralScheduleHomeScreen> {
  String? _view;
  bool _initializedView = false;
  bool _datePickerOpen = false;
  bool _editorSheetOpen = false;
  bool _detailsSheetOpen = false;
  bool _moreOccurrencesSheetOpen = false;
  bool _calendarManagerOpen = false;
  bool _settingsPageOpen = false;
  bool _pendingSheetOpen = false;

  /// 课程移动历史（撤销/重做）：每次移动前快照受影响课程的槽位。
  final List<Map<String, List<ScheduleSlot>>> _undoStack = [];
  final List<Map<String, List<ScheduleSlot>>> _redoStack = [];

  bool get _canUndo => _undoStack.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedView) {
      _view = context.read<TimetableProvider>().generalDefaultView;
      _initializedView = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TimetableProvider>();
    final l10n = AppLocalizations.of(context);
    final selectedDate = provider.selectedGeneralDate;
    final view = normalizeGeneralView(_view ?? provider.generalDefaultView);
    const filter = _GeneralOccurrenceFilter(query: '', colorValue: null);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: InkWell(
          key: const ValueKey('general-date-title-button'),
          borderRadius: BorderRadius.circular(24),
          onTap: _datePickerOpen ? null : () => _pickDate(context, provider),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.appTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  _yearLabel(selectedDate, view, context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
          ),
        ),
        actions: [
          _PendingCoursesAction(
            disabled: _pendingSheetOpen,
            onPressed: () => _openPendingCourses(context, provider),
          ),
          _CalendarManagerAction(
            expanded: MediaQuery.sizeOf(context).width >= 1000,
            disabled: _calendarManagerOpen,
            onPressed: () => _openCalendarManager(context, provider),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.addCourse,
            onPressed: _pendingSheetOpen ? null : () => _openAddCourse(context),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settings,
            onPressed: _settingsPageOpen
                ? null
                : () => _openSettingsPage(context, provider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _editorSheetOpen
            ? null
            : () => _openEditor(context, provider),
        tooltip: l10n.addEvent,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 420;
                  Widget? label(String text) => compact ? null : Text(text);
                  return Row(
                    children: [
                      // 撤销/重做课程移动。
                      IconButton(
                        tooltip: '撤销移动',
                        icon: const Icon(Icons.undo),
                        visualDensity: VisualDensity.compact,
                        onPressed: _canUndo ? _undoMove : null,
                      ),
                      IconButton(
                        tooltip: '恢复移动',
                        icon: const Icon(Icons.redo),
                        visualDensity: VisualDensity.compact,
                        onPressed: _canRedo ? _redoMove : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SegmentedButton<String>(
                          segments: [
                            ButtonSegment(
                              value: generalViewWeek,
                              icon: const Icon(Icons.view_week_outlined),
                              label: label(l10n.viewWeek),
                              tooltip: l10n.viewWeek,
                            ),
                            ButtonSegment(
                              value: generalViewDay,
                              icon: const Icon(Icons.view_day_outlined),
                              label: label(l10n.viewDay),
                              tooltip: l10n.viewDay,
                            ),
                            ButtonSegment(
                              value: generalViewList,
                              icon: const Icon(Icons.list_alt_outlined),
                              label: label(l10n.viewList),
                              tooltip: l10n.viewList,
                            ),
                            ButtonSegment(
                              value: generalViewMonth,
                              icon: const Icon(
                                Icons.calendar_view_month_outlined,
                              ),
                              label: label(l10n.viewMonth),
                              tooltip: l10n.viewMonth,
                            ),
                          ],
                          selected: {view},
                          showSelectedIcon: false,
                          style: compact
                              ? SegmentedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                )
                              : null,
                          onSelectionChanged: (selection) {
                            setState(() {
                              _view = selection.first;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 时间精度调节（矮半弹窗）。
                      IconButton(
                        tooltip: '时间精度调节',
                        icon: const Icon(Icons.zoom_in_map_outlined),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _openTimelinePrecisionSheet(provider),
                      ),
                      // 分享日程。
                      IconButton(
                        tooltip: '分享日程',
                        icon: const Icon(Icons.ios_share),
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            _openShareScheduleSheet(context, provider),
                      ),
                    ],
                  );
                },
              ),
            ),
            if (view != generalViewMonth)
              _ReminderStrip(
                provider: provider,
                filter: filter,
                onOccurrenceTap: (occurrence) =>
                    _openDetails(context, provider, occurrence),
              ),
            Expanded(
              child: ScrollConfiguration(
                behavior: const MaterialScrollBehavior().copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.invertedStylus,
                  },
                ),
                child: ExpressiveSwitcher(
                  child: KeyedSubtree(
                    key: ValueKey(view),
                    child: switch (view) {
                      generalViewDay => _DayCalendarView(
                        date: selectedDate,
                        provider: provider,
                        filter: filter,
                        onDaySelected: provider.setSelectedGeneralDate,
                        onEmptySlotTap: (date) =>
                            _openEditor(context, provider, initialDate: date),
                        onOccurrenceTap: (occurrence) =>
                            _openDetails(context, provider, occurrence),
                        onMoreOccurrencesTap: (occurrences) =>
                            _openMoreOccurrences(
                              context,
                              provider,
                              occurrences,
                            ),
                        onMoveCourse:
                            (
                              occurrence,
                              targetDay,
                              startMinute,
                              deltaMinutes,
                            ) => _moveLinkCourseSlot(
                              context,
                              occurrence,
                              targetDay,
                              startMinute,
                              deltaMinutes,
                            ),
                      ),
                      generalViewList => _ListCalendarView(
                        date: selectedDate,
                        provider: provider,
                        filter: filter,
                        onToday: () => _goToToday(provider),
                        onPickDate: () => _pickDate(context, provider),
                        onOccurrenceTap: (occurrence) =>
                            _openDetails(context, provider, occurrence),
                      ),
                      generalViewMonth => _MonthCalendarView(
                        date: selectedDate,
                        provider: provider,
                        filter: filter,
                        onDaySelected: provider.setSelectedGeneralDate,
                        onEmptySlotTap: (date) =>
                            _openEditor(context, provider, initialDate: date),
                        onOccurrenceTap: (occurrence) =>
                            _openDetails(context, provider, occurrence),
                      ),
                      _ => _WeekCalendarView(
                        date: selectedDate,
                        provider: provider,
                        filter: filter,
                        onDaySelected: provider.setSelectedGeneralDate,
                        onEmptySlotTap: (date) =>
                            _openEditor(context, provider, initialDate: date),
                        onOccurrenceTap: (occurrence) =>
                            _openDetails(context, provider, occurrence),
                        onMoreOccurrencesTap: (occurrences) =>
                            _openMoreOccurrences(
                              context,
                              provider,
                              occurrences,
                            ),
                        onMoveCourse:
                            (
                              occurrence,
                              targetDay,
                              startMinute,
                              deltaMinutes,
                            ) => _moveLinkCourseSlot(
                              context,
                              occurrence,
                              targetDay,
                              startMinute,
                              deltaMinutes,
                            ),
                      ),
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _goToToday(TimetableProvider provider) async {
    await provider.setSelectedGeneralDate(DateTime.now());
  }

  void _setUiBusyFlag(void Function() update) {
    if (mounted) {
      setState(update);
    } else {
      update();
    }
  }

  Future<void> _pickDate(
    BuildContext context,
    TimetableProvider provider,
  ) async {
    if (_datePickerOpen) {
      return;
    }
    _setUiBusyFlag(() => _datePickerOpen = true);
    final firstDate = DateTime(1970);
    final lastDate = DateTime(2100);
    try {
      final picked = await showDatePicker(
        context: context,
        initialDate: _clampDate(
          provider.selectedGeneralDate,
          firstDate,
          lastDate,
        ),
        firstDate: firstDate,
        lastDate: lastDate,
      );
      if (!mounted || picked == null) {
        return;
      }
      await provider.setSelectedGeneralDate(picked);
    } finally {
      _setUiBusyFlag(() => _datePickerOpen = false);
    }
  }

  Future<void> _openEditor(
    BuildContext context,
    TimetableProvider provider, {
    DateTime? initialDate,
    GeneralEvent? event,
  }) async {
    if (_editorSheetOpen) {
      return;
    }
    _setUiBusyFlag(() => _editorSheetOpen = true);
    final canDismiss = provider.closeGeneralEventPopupOnOutsideTap;
    try {
      final result = await showAppModalSheet<GeneralEventEditorResult>(
        context: context,
        isDismissible: canDismiss,
        enableDrag: canDismiss,
        maxWidth: appSheetWidthMedium,
        builder: (sheetContext) => GeneralEventEditorSheet(
          initialEvent: event,
          initialDate: initialDate ?? provider.selectedGeneralDate,
          calendars: provider.generalSchedules,
          activeCalendarId: provider.activeGeneralSchedule.id,
        ),
      );

      if (result == null || !mounted || !context.mounted) return;

      if (result.delete && event != null) {
        _removeLinkCourseSlotForGridEvent(event.id);
        try {
          await provider.deleteGeneralEvent(event.id);
        } catch (_) {
          if (!mounted || !context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).saveFailedRetry),
            ),
          );
        }
      } else if (result.event != null) {
        try {
          await provider.saveGeneralEvent(result.event!);
        } catch (_) {
          if (!mounted || !context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).saveFailedRetry),
            ),
          );
        }
      }
    } finally {
      _setUiBusyFlag(() => _editorSheetOpen = false);
    }
  }

  Future<void> _openDetails(
    BuildContext context,
    TimetableProvider provider,
    GeneralEventOccurrence occurrence,
  ) async {
    if (_detailsSheetOpen) {
      return;
    }
    _setUiBusyFlag(() => _detailsSheetOpen = true);
    final canDismiss = provider.closeGeneralEventPopupOnOutsideTap;
    try {
      await showAppModalSheet<void>(
        context: context,
        isDismissible: canDismiss,
        enableDrag: canDismiss,
        maxWidth: appSheetWidthCompact,
        builder: (sheetContext) => GeneralEventDetailsSheet(
          occurrence: occurrence,
          isReminderHandled: provider.isGeneralReminderHandled(occurrence),
          onEdit: () {
            Navigator.of(sheetContext).pop();
            return _openEditor(context, provider, event: occurrence.event);
          },
          onDismissReminder: () async {
            final messenger = ScaffoldMessenger.of(context);
            final message = AppLocalizations.of(context).reminderHandled;
            await provider.dismissGeneralReminder(occurrence);
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            if (mounted) {
              messenger.showSnackBar(SnackBar(content: Text(message)));
            }
          },
          onRestoreReminder: () async {
            final messenger = ScaffoldMessenger.of(context);
            final message = AppLocalizations.of(context).reminderRestored;
            await provider.restoreGeneralReminder(occurrence);
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            if (mounted) {
              messenger.showSnackBar(SnackBar(content: Text(message)));
            }
          },
          onDuplicate: () async {
            final messenger = ScaffoldMessenger.of(context);
            final message = AppLocalizations.of(context).eventDuplicated;
            await provider.duplicateGeneralOccurrence(occurrence);
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            if (mounted) {
              messenger.showSnackBar(SnackBar(content: Text(message)));
            }
          },
          onDeleteThis: () async {
            _removeLinkCourseSlotForGridEvent(occurrence.event.id);
            await provider.deleteGeneralOccurrence(occurrence);
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          },
          onDeleteFuture: occurrence.event.recurrenceRule.isRepeating
              ? () async {
                  await provider.deleteFutureGeneralOccurrences(occurrence);
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                }
              : null,
          onDeleteAll: () async {
            _removeLinkCourseSlotForGridEvent(occurrence.event.id);
            await provider.deleteGeneralEvent(occurrence.event.id);
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          },
        ),
      );
    } finally {
      _setUiBusyFlag(() => _detailsSheetOpen = false);
    }
  }

  Future<void> _openMoreOccurrences(
    BuildContext context,
    TimetableProvider provider,
    List<GeneralEventOccurrence> occurrences,
  ) async {
    if (_moreOccurrencesSheetOpen || occurrences.isEmpty) {
      return;
    }
    _setUiBusyFlag(() => _moreOccurrencesSheetOpen = true);
    final canDismiss = provider.closeGeneralEventPopupOnOutsideTap;
    GeneralEventOccurrence? selectedOccurrence;
    try {
      selectedOccurrence = await showAppModalSheet<GeneralEventOccurrence>(
        context: context,
        isDismissible: canDismiss,
        enableDrag: canDismiss,
        maxWidth: appSheetWidthCompact,
        builder: (sheetContext) => _MoreGeneralOccurrencesSheet(
          occurrences: occurrences,
          onOccurrenceTap: (occurrence) =>
              Navigator.of(sheetContext).pop(occurrence),
        ),
      );
    } finally {
      _setUiBusyFlag(() => _moreOccurrencesSheetOpen = false);
    }
    if (selectedOccurrence != null && mounted && context.mounted) {
      await _openDetails(context, provider, selectedOccurrence);
    }
  }

  Future<void> _openCalendarManager(
    BuildContext context,
    TimetableProvider provider,
  ) async {
    if (_calendarManagerOpen) {
      return;
    }
    _setUiBusyFlag(() => _calendarManagerOpen = true);
    final canDismiss = provider.closeGeneralEventPopupOnOutsideTap;
    try {
      await showAppModalSheet<void>(
        context: context,
        isDismissible: canDismiss,
        enableDrag: canDismiss,
        maxWidth: 620,
        builder: (sheetContext) =>
            ChangeNotifierProvider<TimetableProvider>.value(
              value: provider,
              child: const _CalendarManagerSheet(),
            ),
      );
    } finally {
      _setUiBusyFlag(() => _calendarManagerOpen = false);
    }
  }

  Future<void> _openSettingsPage(
    BuildContext context,
    TimetableProvider provider,
  ) async {
    if (_settingsPageOpen) {
      return;
    }
    _setUiBusyFlag(() => _settingsPageOpen = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChangeNotifierProvider<TimetableProvider>.value(
            value: provider,
            child: const SettingsPage(),
          ),
        ),
      );
    } finally {
      _setUiBusyFlag(() => _settingsPageOpen = false);
    }
  }

  /// 网格删除联动：删除"LinkStudy 课表"里的课程日程时，
  /// 同步移除对应课程槽位（课程回到未排课池），避免 sync 重建已删除的事件。
  void _removeLinkCourseSlotForGridEvent(String eventId) {
    if (!eventId.startsWith('ls_')) return;
    unawaited(
      LinkCourseStore.instance.removeSlotForCourse(eventId.substring(3)),
    );
  }

  /// 长按拖拽课程日程到新时间/新日期：更新 LinkStudy 槽位，
  /// 整门课所有段一起平移（保持段间相对间隔），网格同步自动重建事件。
  void _moveLinkCourseSlot(
    BuildContext context,
    GeneralEventOccurrence occurrence,
    DateTime targetDay,
    int startMinute,
    int deltaMinutes,
  ) {
    final eventId = occurrence.event.id;
    if (!eventId.startsWith(LinkStudyGridSync.eventIdPrefix)) return;
    final courseId = eventId.substring(LinkStudyGridSync.eventIdPrefix.length);
    final store = LinkCourseStore.instance;
    final slots = store.slots.where((s) => s.courseId == courseId).toList()
      ..sort((a, b) {
        final da = a.epochDay ?? 0;
        final db = b.epochDay ?? 0;
        return da != db
            ? da.compareTo(db)
            : a.startMinute.compareTo(b.startMinute);
      });
    if (slots.isEmpty) return;
    // 找到被拖动的段：按起止时间匹配 occurrence。
    final draggedStart = occurrence.start.hour * 60 + occurrence.start.minute;
    final draggedEnd = occurrence.end.hour * 60 + occurrence.end.minute;
    var anchorIndex = slots.indexWhere(
      (s) => s.startMinute == draggedStart && s.endMinute == draggedEnd,
    );
    if (anchorIndex < 0) anchorIndex = 0;
    final anchor = slots[anchorIndex.clamp(0, slots.length - 1)];
    final anchorDay = anchor.epochDay ?? 0;
    final day = DateTime(targetDay.year, targetDay.month, targetDay.day);
    final targetEpochDay = epochDayOf(day);
    // 无实际变化（时间与日期都未变）时跳过，避免"恢复原位"的无效重写。
    if (targetEpochDay == anchorDay && startMinute == anchor.startMinute) {
      return;
    }
    // 移动前快照该课程槽位（用于撤销）。
    _undoStack.add({
      courseId: [
        for (final s in slots)
          ScheduleSlot(
            courseId: s.courseId,
            epochDay: s.epochDay,
            weekday: s.weekday,
            startMinute: s.startMinute,
            endMinute: s.endMinute,
            colorValue: s.colorValue,
          ),
      ],
    });
    _redoStack.clear();
    setState(() {});
    unawaited(
      store.moveSlot(
        courseId,
        epochDay: targetEpochDay,
        weekday: day.weekday,
        startMinute: startMinute,
        anchorSlotIndex: anchorIndex,
      ),
    );
  }

  /// 撤销上一次课程移动：恢复该课程移动前的槽位。
  void _undoMove() {
    if (!_canUndo) return;
    final snapshot = _undoStack.removeLast();
    _redoStack.add(snapshot);
    _restoreSlotSnapshot(snapshot);
  }

  /// 重做被撤销的课程移动。
  void _redoMove() {
    if (!_canRedo) return;
    final snapshot = _redoStack.removeLast();
    _undoStack.add(snapshot);
    _restoreSlotSnapshot(snapshot);
  }

  /// 用快照覆盖课程槽位（撤销/重做共用）。
  void _restoreSlotSnapshot(Map<String, List<ScheduleSlot>> snapshot) {
    final store = LinkCourseStore.instance;
    final courseId = snapshot.keys.first;
    final slots = snapshot[courseId]!;
    final next = <ScheduleSlot>[
      for (final s in store.slots)
        if (s.courseId != courseId) s,
      ...slots,
    ];
    store.replaceSlots(next);
    setState(() {});
  }

  /// 时间精度调节（矮半弹窗）。
  void _openTimelinePrecisionSheet(TimetableProvider provider) {
    showTimelinePrecisionSheet(context, provider: provider);
  }

  /// 分享日程（当天 / 7 天，图片 / md / json / 纯文字）。
  void _openShareScheduleSheet(
    BuildContext context,
    TimetableProvider provider,
  ) {
    showShareScheduleSheet(context, provider: provider);
  }

  /// 打开未排课池：勾选课程 → AI 排课设置 → 完成。
  /// 首页右上角 + ：打开"添加课程"半弹窗（填 URL/名称/时长，与悬浮窗同一入库入口）。
  Future<void> _openAddCourse(BuildContext context) async {
    if (_pendingSheetOpen) return;
    _setUiBusyFlag(() => _pendingSheetOpen = true);
    try {
      await showAddCourseSheet(context, store: LinkCourseStore.instance);
    } finally {
      _setUiBusyFlag(() => _pendingSheetOpen = false);
    }
  }

  /// AI 排课进行中时改为打开进度面板（查看思考过程与结果）。
  Future<void> _openPendingCourses(
    BuildContext context,
    TimetableProvider provider,
  ) async {
    if (_pendingSheetOpen) {
      return;
    }
    _setUiBusyFlag(() => _pendingSheetOpen = true);
    try {
      final runner = AiScheduleRunner.instance;
      if (runner.isRunning || runner.hasUnviewedResult) {
        final task = runner.task;
        await showAppModalSheet<void>(
          context: context,
          maxWidth: appSheetWidthMedium,
          builder: (sheetContext) => AiScheduleProgressSheet(
            store: LinkCourseStore.instance,
            onRerun: (task) async {
              // 一键重排：清空本次课程槽位（课程回未排课池）→ 关闭面板 → 重新打开设置弹窗。
              if (!sheetContext.mounted) return;
              Navigator.of(sheetContext).pop();
              await LinkCourseStore.instance.clearSlotsForCourses(
                task.courseIds,
              );
              runner.reset();
              if (!mounted || !context.mounted) return;
              await _openPendingCourses(context, provider);
            },
          ),
        );
        runner.markViewed();
        return;
      }
      final selected = await showAppModalSheet<List<String>>(
        context: context,
        maxWidth: appSheetWidthMedium,
        builder: (sheetContext) =>
            CoursePendingSheet(store: LinkCourseStore.instance),
      );
      if (selected == null ||
          selected.isEmpty ||
          !mounted ||
          !context.mounted) {
        return;
      }
      await showAppModalSheet<void>(
        context: context,
        maxWidth: appSheetWidthMedium,
        builder: (sheetContext) => AiScheduleSetupSheet(
          store: LinkCourseStore.instance,
          provider: provider,
          courseIds: selected,
        ),
      );
    } finally {
      _setUiBusyFlag(() => _pendingSheetOpen = false);
    }
  }
}

/// 排课按钮：展示未排课数量角标；AI 排课进行中时显示进度状态，点击查看进度。
class _PendingCoursesAction extends StatelessWidget {
  const _PendingCoursesAction({
    required this.disabled,
    required this.onPressed,
  });

  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final store = LinkCourseStore.instance;
    final runner = AiScheduleRunner.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([store, runner]),
      builder: (context, child) {
        final running = runner.isRunning;
        final count = store.pendingCount;
        if (running) {
          return IconButton(
            tooltip: 'AI 排课中，点击查看进度',
            onPressed: disabled ? null : onPressed,
            icon: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        }
        return Badge(
          isLabelVisible: count > 0,
          label: Text('$count'),
          child: IconButton(
            icon: const Icon(Icons.event_note_outlined),
            tooltip: '未排课课程（$count）',
            onPressed: disabled ? null : onPressed,
          ),
        );
      },
    );
  }
}

class _MoreGeneralOccurrencesSheet extends StatelessWidget {
  const _MoreGeneralOccurrencesSheet({
    required this.occurrences,
    required this.onOccurrenceTap,
  });

  final List<GeneralEventOccurrence> occurrences;
  final ValueChanged<GeneralEventOccurrence> onOccurrenceTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final first = occurrences.first;
    return AppSheetScaffold(
      title: Text(l10n.monthDayEvents(first.start.day, occurrences.length)),
      subtitle: Text(
        '${_formatDate(first.start)}  ${_formatOccurrenceTime(context, first)}',
      ),
      heightFactor: occurrences.length > 5 ? 0.72 : null,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final occurrence in occurrences)
            _GeneralListOccurrenceTile(
              occurrence: occurrence,
              onTap: () => onOccurrenceTap(occurrence),
            ),
        ],
      ),
    );
  }
}

class _CalendarManagerAction extends StatelessWidget {
  const _CalendarManagerAction({
    required this.expanded,
    required this.disabled,
    required this.onPressed,
  });

  final bool expanded;
  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final callback = disabled ? null : onPressed;
    if (!expanded) {
      return IconButton(
        icon: const Icon(Icons.calendar_month_outlined),
        tooltip: l10n.calendars,
        onPressed: callback,
      );
    }

    return Tooltip(
      message: l10n.calendars,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: TextButton.icon(
          onPressed: callback,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text(l10n.calendars),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
    );
  }
}

List<DateTime> _visibleWeekDays(DateTime weekStart, bool showWeekends) {
  return [
    for (var i = 0; i < 7; i++)
      if (showWeekends || i < 5) weekStart.add(Duration(days: i)),
  ];
}

class _GeneralOccurrenceFilter {
  const _GeneralOccurrenceFilter({
    required this.query,
    required this.colorValue,
  });

  final String query;
  final int? colorValue;

  bool get isActive => query.trim().isNotEmpty || colorValue != null;

  GeneralOccurrenceQuery toQuery({
    required DateTime startInclusive,
    required DateTime endExclusive,
    bool onlyVisibleCalendars = true,
  }) {
    return GeneralOccurrenceQuery(
      startInclusive: startInclusive,
      endExclusive: endExclusive,
      onlyVisibleCalendars: onlyVisibleCalendars,
      searchQuery: query,
      colorValue: colorValue,
    );
  }
}

String _yearLabel(DateTime date, String view, BuildContext context) {
  if (view == generalViewMonth) {
    final localizations = MaterialLocalizations.of(context);
    return localizations.formatMonthYear(date);
  }
  if (view != generalViewWeek) {
    return date.year.toString();
  }
  final start = startOfWeekMonday(date);
  final end = start.add(const Duration(days: 6));
  return start.year == end.year
      ? '${start.year}'
      : '${start.year} / ${end.year}';
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

DateTime _clampDate(DateTime date, DateTime firstDate, DateTime lastDate) {
  if (date.isBefore(firstDate)) {
    return firstDate;
  }
  if (date.isAfter(lastDate)) {
    return lastDate;
  }
  return date;
}

String _formatTime(DateTime date) {
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String _formatOccurrenceTime(
  BuildContext context,
  GeneralEventOccurrence occurrence,
) {
  if (occurrence.isAllDay) {
    return AppLocalizations.of(context).allDay;
  }
  if (!_sameDay(occurrence.start, occurrence.end)) {
    return '${_formatDate(occurrence.start)} ${_formatTime(occurrence.start)} - ${_formatDate(occurrence.end)} ${_formatTime(occurrence.end)}';
  }
  return '${_formatTime(occurrence.start)} - ${_formatTime(occurrence.end)}';
}

String _weekdayLabel(BuildContext context, DateTime date) {
  final l10n = AppLocalizations.of(context);
  return switch (date.weekday) {
    DateTime.monday => l10n.weekdayShortMonday,
    DateTime.tuesday => l10n.weekdayShortTuesday,
    DateTime.wednesday => l10n.weekdayShortWednesday,
    DateTime.thursday => l10n.weekdayShortThursday,
    DateTime.friday => l10n.weekdayShortFriday,
    DateTime.saturday => l10n.weekdayShortSaturday,
    _ => l10n.weekdayShortSunday,
  };
}

String _dateKey(DateTime date) => normalizeDateOnly(date).toIso8601String();

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _occurrenceIntersectsDay(GeneralEventOccurrence occurrence, DateTime day) {
  final start = normalizeDateOnly(day);
  final end = start.add(const Duration(days: 1));
  return occurrence.end.isAfter(start) && occurrence.start.isBefore(end);
}

int _nowMinutes() {
  final now = DateTime.now();
  return now.hour * 60 + now.minute;
}

int _snapMinutes(int minutes, int gridMinutes) {
  final step = gridMinutes.clamp(15, 60).toInt();
  return (minutes / step).round() * step;
}

Color _readableColor(Color color) {
  return color.computeLuminance() > 0.42 ? Colors.black87 : Colors.white;
}

int _nextCalendarColor(List<GeneralSchedule> schedules) {
  return generalCalendarSlotColorValues[schedules.length %
      generalCalendarSlotColorValues.length];
}
