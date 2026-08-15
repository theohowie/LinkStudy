import 'package:flutter/material.dart';

import '../courses/ai_scheduler.dart';
import '../courses/link_course.dart';
import '../providers/timetable_provider.dart';
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
    this.scheduler,
  });

  final LinkCourseStore store;
  final TimetableProvider provider;
  final List<String> courseIds;
  final AiScheduleSettings? settings;
  final AiScheduler? scheduler;

  @override
  State<AiScheduleSetupSheet> createState() => _AiScheduleSetupSheetState();
}

class _AiScheduleSetupSheetState extends State<AiScheduleSetupSheet> {
  late final AiScheduleSettings _settings =
      widget.settings ?? AiScheduleSettings();
  late final AiScheduler _scheduler = widget.scheduler ?? AiScheduler();

  StudyIntensity _intensity = StudyIntensity.medium;
  int _days = 7;
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _timePreference = TextEditingController();
  bool _running = false;

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
    final slots = availability.isEmpty ? const <AvailabilitySlot>[] : availability.first;
    return slots
        .map((s) =>
            '${_hhmm(s.startMinute)}-${_hhmm(s.endMinute)}')
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
    if (_running) return;
    final prefs = AiSchedulePrefs(
      intensity: _intensity,
      days: _days,
      notes: _notes.text.trim(),
      timePreference: _timePreference.text.trim(),
    );
    setState(() => _running = true);
    try {
      final provider = widget.provider;
      final availability = availabilityFromDayWindow(
        startMinute: provider.generalDayStartMinute,
        lunchStartMinute: provider.generalLunchStartMinute,
        lunchEndMinute: provider.generalLunchEndMinute,
        endMinute: provider.generalDayEndMinute,
      );
      final config = await _settings.loadConfig(
        windowDescription: _windowDescription,
      );
      final courses = widget.courseIds
          .map(widget.store.courseById)
          .whereType<LinkCourse>()
          .toList();
      final outcome = await _scheduler.schedule(
        courses: courses,
        prefs: prefs,
        config: config,
        localeCode: provider.localeCode,
      );

      switch (outcome) {
        case AiScheduleOutcomeSuccess(:final value):
          final ordered = value.ordered
              .where((o) => widget.courseIds.contains(o.courseId))
              .toList();
          final result = await widget.store.scheduleWithOrder(
            courseIds: widget.courseIds,
            ordered: ordered,
            days: prefs.days,
            availabilityByWeekday: availability,
          );
          await _settings.saveSetupPrefs(prefs);
          final failNote = result.failures.isEmpty
              ? ''
              : '，${result.failures.length} 门未能排上';
          _showSnack('AI 排课完成：${result.placements.length} 门已安排$failNote');
          if (mounted) Navigator.of(context).pop();
        case AiScheduleOutcomeError(:final error):
          // 不自动回退排课：课程保留在未排课池中，用户处理（如配置/更换模型）后可重新 AI 排课。
          await _settings.saveSetupPrefs(prefs);
          _showSnack('AI 排课失败：${error.message}（课程仍留在未排课池，可修改后重试）');
          if (mounted) setState(() => _running = false);
      }
    } catch (e) {
      _showSnack('排课出错：$e');
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSheetScaffold(
      title: const Text('AI 智能排课'),
      subtitle: const Text('告诉 AI 你的学习节奏，剩下的交给它'),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _running ? null : _run,
          child: _running
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('开始 AI 排课'),
        ),
      ],
      child: Column(
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
            onSelectionChanged: _running
                ? null
                : (selection) => setState(() => _intensity = selection.first),
          ),
          const SizedBox(height: 16),
          Text('计划 $_days 天学完', style: theme.textTheme.titleSmall),
          Slider(
            value: _days.toDouble(),
            min: 1,
            max: 14,
            divisions: 13,
            label: '$_days 天',
            onChanged: _running
                ? null
                : (v) => setState(() => _days = v.round()),
          ),
          const SizedBox(height: 8),
          Text(
            '备注（可选）',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            enabled: !_running,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: '这几天哪些时间已有安排？如：周一下午有课、周三晚上有会…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '时间偏好（可选，留空=全天）',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _timePreference,
            enabled: !_running,
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
