import 'dart:async';

import 'package:flutter/material.dart';

import '../courses/ai_schedule_runner.dart';
import '../courses/ai_scheduler.dart';
import '../courses/link_course.dart';
import '../providers/timetable_provider.dart';
import 'ai_schedule_progress_sheet.dart';
import 'app_modal_sheet.dart';

/// AI 排课设置弹窗：学习强度 / 计划天数 / 备注（已有安排）/ 时间偏好。
/// 记住上次选择；"开始 AI 排课"在此完成：组装 Prompt → 调 AI → 本地落位 → 网格同步。
/// AI 失败时自动回退本地贪心算法，并用气泡提示错误信息。
class AiScheduleSetupSheet extends StatefulWidget {
  const AiScheduleSetupSheet({
    super.key,
    required this.store,
    required this.provider,
    required this.courseIds,
    this.settings,
  });

  final LinkCourseStore store;
  final TimetableProvider provider;
  final List<String> courseIds;
  final AiScheduleSettings? settings;

  @override
  State<AiScheduleSetupSheet> createState() => _AiScheduleSetupSheetState();
}

class _AiScheduleSetupSheetState extends State<AiScheduleSetupSheet> {
  late final AiScheduleSettings _settings =
      widget.settings ?? AiScheduleSettings();

  StudyIntensity _intensity = StudyIntensity.medium;
  int _days = 7;
  ScheduleStartMode _startMode = ScheduleStartMode.now;
  bool _scheduling = false;
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _timePreference = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedPrefs();
  }

  @override
  void dispose() {
    _notes.dispose();
    _timePreference.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPrefs() async {
    final saved = await _settings.loadSetupPrefs();
    if (!mounted || saved == null) return;
    setState(() {
      _intensity = saved.intensity;
      _days = saved.days.clamp(1, 14);
      _notes.text = saved.notes;
      _timePreference.text = saved.timePreference;
      _startMode = saved.startMode;
    });
  }

  String get _windowDescription {
    final provider = widget.provider;
    final availability = availabilityFromDayWindow(
      startMinute: provider.generalDayStartMinute,
      lunchStartMinute: provider.generalLunchStartMinute,
      lunchEndMinute: provider.generalLunchEndMinute,
      endMinute: provider.generalDayEndMinute,
    );
    final slots = availability.isEmpty
        ? const <AvailabilitySlot>[]
        : availability.first;
    return slots
        .map((s) => '${_hhmm(s.startMinute)}-${_hhmm(s.endMinute)}')
        .join(' 与 ');
  }

  static String _hhmm(int minute) {
    final h = (minute ~/ 60).toString().padLeft(2, '0');
    final m = (minute % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run() async {
    if (_scheduling) return;
    if (AiScheduleRunner.instance.isRunning) {
      _showSnack('已有排课任务进行中，请稍候');
      return;
    }
    final provider = widget.provider;
    final prefs = AiSchedulePrefs(
      intensity: _intensity,
      days: _days,
      notes: _notes.text.trim(),
      timePreference: _timePreference.text.trim(),
      startMode: _startMode,
    );
    final availability = availabilityFromDayWindow(
      startMinute: provider.generalDayStartMinute,
      lunchStartMinute: provider.generalLunchStartMinute,
      lunchEndMinute: provider.generalLunchEndMinute,
      endMinute: provider.generalDayEndMinute,
    );
    // 后台静默排课：弹窗切换为"排课中"状态（不关闭），可查看进度或主动退出，后台继续执行。
    unawaited(
      AiScheduleRunner.instance.start(
        courseIds: widget.courseIds,
        prefs: prefs,
        availability: availability,
        windowDescription: _windowDescription,
        localeCode: provider.localeCode,
      ),
    );
    if (mounted) {
      setState(() => _scheduling = true);
      _showSnack('已开始后台排课，完成时会通知你，可点"排课中…"查看进度或退出');
    }
  }

  Future<void> _openProgress() async {
    await showAppModalSheet<void>(
      context: context,
      maxWidth: appSheetWidthMedium,
      builder: (sheetContext) => AiScheduleProgressSheet(store: widget.store),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSheetScaffold(
      heightFactor: 0.84,
      title: const Text('AI 智能排课'),
      subtitle: const Text('告诉 AI 你的学习节奏，剩下的交给它'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_scheduling ? '退出（后台继续）' : '取消'),
        ),
        FilledButton(
          onPressed: _scheduling ? _openProgress : _run,
          child: _scheduling
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('排课中…'),
                  ],
                )
              : const Text('开始 AI 排课'),
        ),
      ],
      child: _scheduling
          ? AiScheduleConversation(store: widget.store)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('学习强度', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<StudyIntensity>(
                  segments: const [
                    ButtonSegment(
                      value: StudyIntensity.relaxed,
                      icon: Icon(Icons.spa_outlined),
                      label: Text('轻松 🍃'),
                    ),
                    ButtonSegment(
                      value: StudyIntensity.medium,
                      icon: Icon(Icons.balance_outlined),
                      label: Text('中等 ⚖️'),
                    ),
                    ButtonSegment(
                      value: StudyIntensity.stressed,
                      icon: Icon(Icons.local_fire_department_outlined),
                      label: Text('压力 🔥'),
                    ),
                  ],
                  selected: {_intensity},
                  onSelectionChanged: (selection) =>
                      setState(() => _intensity = selection.first),
                ),
                const SizedBox(height: 16),
                Text('计划 $_days 天学完', style: theme.textTheme.titleSmall),
                Slider(
                  value: _days.toDouble(),
                  min: 1,
                  max: 14,
                  divisions: 13,
                  label: '$_days 天',
                  onChanged: (v) => setState(() => _days = v.round()),
                ),
                const SizedBox(height: 16),
                Text('开始时间', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<ScheduleStartMode>(
                  segments: const [
                    ButtonSegment(
                      value: ScheduleStartMode.now,
                      icon: Icon(Icons.play_arrow_outlined),
                      label: Text('从现在开始'),
                    ),
                    ButtonSegment(
                      value: ScheduleStartMode.tomorrow,
                      icon: Icon(Icons.event_available_outlined),
                      label: Text('从明天开始'),
                    ),
                  ],
                  selected: {_startMode},
                  onSelectionChanged: (selection) =>
                      setState(() => _startMode = selection.first),
                ),
                const SizedBox(height: 8),
                Text('备注（可选）', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _notes,
                  enabled: true,
                  maxLines: 2,
                  minLines: 1,
                  decoration: const InputDecoration(
                    hintText: '这几天哪些时间已有安排？如：周一下午有课、周三晚上有会…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                Text('时间偏好（可选，留空=全天）', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _timePreference,
                  enabled: true,
                  decoration: const InputDecoration(
                    hintText: '如：晚上 19:00-22:00、每天上午',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '每天可用时间窗：$_windowDescription（在设置-通用显示设置中调整）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}
