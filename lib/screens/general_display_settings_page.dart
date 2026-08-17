import '../models/general_models.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_locale.dart' as app_locale;
import '../l10n/app_localizations.dart';
import '../providers/timetable_provider.dart';
import '../widgets/sked_dropdown_menu.dart';
import '../widgets/settings_list.dart';

class GeneralDisplaySettingsPage extends StatelessWidget {
  const GeneralDisplaySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Consumer<TimetableProvider>(
      builder: (context, provider, child) {
        final theme = Theme.of(context);
        final localeCode = app_locale.normalizeLocaleCode(provider.localeCode);
        return Scaffold(
          appBar: AppBar(title: Text(l10n.generalDisplaySettings)),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              SettingsSectionHeader(title: l10n.generalDefaultViewSection),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SkedDropdownMenu<String>(
                  initialSelection: provider.generalDefaultView,
                  label: Text(l10n.defaultView),
                  leadingIcon: const Icon(Icons.space_dashboard_outlined),
                  expandedInsets: EdgeInsets.zero,
                  dropdownMenuEntries: [
                    DropdownMenuEntry(
                      value: generalViewWeek,
                      label: l10n.viewWeek,
                    ),
                    DropdownMenuEntry(
                      value: generalViewDay,
                      label: l10n.viewDay,
                    ),
                    DropdownMenuEntry(
                      value: generalViewList,
                      label: l10n.viewList,
                    ),
                    DropdownMenuEntry(
                      value: generalViewMonth,
                      label: l10n.viewMonth,
                    ),
                  ],
                  onSelected: (value) {
                    if (value != null) {
                      provider.updateGeneralDisplaySettings(defaultView: value);
                    }
                  },
                ),
              ),
              SettingsSectionHeader(title: l10n.generalScheduleDisplaySection),
              SettingsSwitchTile(
                icon: Icons.weekend_outlined,
                title: l10n.showWeekends,
                value: provider.generalShowWeekends,
                onChanged: (value) =>
                    provider.updateGeneralDisplaySettings(showWeekends: value),
              ),
              if (localeCode == 'zh' || localeCode == 'zh-Hant')
                SettingsSwitchTile(
                  icon: Icons.brightness_2_outlined,
                  title: l10n.showLunarCalendar,
                  value: provider.generalShowLunarCalendar,
                  onChanged: (value) => provider.updateGeneralDisplaySettings(
                    showLunarCalendar: value,
                  ),
                ),
              SettingsSectionHeader(title: l10n.generalTimeGridSection),
              _TimeSettingTile(
                icon: Icons.access_time,
                title: l10n.startHour,
                minute: provider.generalDayStartMinute,
                onTap: () => _pickTime(
                  context,
                  provider,
                  initialMinute: provider.generalDayStartMinute,
                  onPicked: (minute) => provider.updateGeneralDisplaySettings(
                    dayStartMinute: minute,
                  ),
                ),
              ),
              _TimeSettingTile(
                icon: Icons.access_time,
                title: l10n.endHour,
                minute: provider.generalDayEndMinute,
                onTap: () => _pickTime(
                  context,
                  provider,
                  initialMinute: provider.generalDayEndMinute,
                  onPicked: (minute) => provider.updateGeneralDisplaySettings(
                    dayEndMinute: minute,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SettingsSectionHeader(title: '固定无法安排日程时间段'),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  '这些时间段不会安排课程，可添加多个'
                  '（如 12:00-13:00 午饭、13:00-14:00 午休、18:00-19:00 晚饭）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (provider.generalFixedBlocks.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                  child: Text(
                    '暂无固定时间段',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (var i = 0; i < provider.generalFixedBlocks.length; i++)
                  _FixedBlockTile(
                    block: provider.generalFixedBlocks[i],
                    onTap: () => _editFixedBlock(context, provider, i),
                    onDelete: () => _deleteFixedBlock(context, provider, i),
                  ),
              SettingsListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: '添加时间段',
                trailing: const Icon(Icons.add),
                onTap: () => _addFixedBlock(context, provider),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SkedDropdownMenu<int>(
                  initialSelection: provider.generalTimeGridMinutes,
                  label: Text(l10n.timeGridDensity),
                  leadingIcon: const Icon(Icons.grid_4x4_outlined),
                  expandedInsets: EdgeInsets.zero,
                  dropdownMenuEntries: [
                    DropdownMenuEntry(
                      value: 15,
                      label: l10n.timeGridMinutes(15),
                    ),
                    DropdownMenuEntry(
                      value: 30,
                      label: l10n.timeGridMinutes(30),
                    ),
                    DropdownMenuEntry(
                      value: 60,
                      label: l10n.timeGridMinutes(60),
                    ),
                  ],
                  onSelected: (value) {
                    if (value != null) {
                      provider.updateGeneralDisplaySettings(
                        timeGridMinutes: value,
                      );
                    }
                  },
                ),
              ),
              _TimelinePrecisionTile(
                value: provider.generalTimelineUnitMinutes,
                onChanged: (value) => provider.updateGeneralDisplaySettings(
                  timelineUnitMinutes: value,
                ),
              ),
              SettingsSectionHeader(title: l10n.generalPopupSection),
              SettingsSwitchTile(
                icon: Icons.open_in_full_outlined,
                title: l10n.closePopupOnOutsideTap,
                value: provider.closeGeneralEventPopupOnOutsideTap,
                onChanged: (value) => provider.updateGeneralDisplaySettings(
                  closeEventPopupOnOutsideTap: value,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 时间线时间精度设置：滑块无级调节(5-480 分钟/刻度)，也可直接输入数字。
class _TimelinePrecisionTile extends StatefulWidget {
  const _TimelinePrecisionTile({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_TimelinePrecisionTile> createState() => _TimelinePrecisionTileState();
}

class _TimelinePrecisionTileState extends State<_TimelinePrecisionTile> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value}',
  );

  @override
  void didUpdateWidget(covariant _TimelinePrecisionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        _controller.text != '${widget.value}') {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = '${widget.value}';
      return;
    }
    final clamped = parsed.clamp(5, 480);
    if (clamped != parsed) {
      _controller.text = '$clamped';
    }
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.zoom_in_map_outlined, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '时间精度（分钟/刻度）',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: 88,
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    suffixText: '分',
                  ),
                  onSubmitted: (_) => _commit(),
                  onEditingComplete: _commit,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '当前：${widget.value} 分钟/刻度'
            '（${widget.value >= 60 ? '${widget.value ~/ 60} 小时' : ''}'
            '${widget.value < 60
                ? ''
                : widget.value % 60 == 0
                ? ''
                : ' ${widget.value % 60} 分'}'
            '${widget.value < 60 ? '$widget.value 分钟' : ''}）'
            ' · 放大最小 5 分钟，缩小最大 8 小时',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Slider(
            value: widget.value.toDouble(),
            min: 5,
            max: 480,
            divisions: 475,
            label: '${widget.value} 分钟',
            onChanged: (v) => widget.onChanged(v.round()),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('5 分', style: theme.textTheme.labelSmall),
              Text('1 小时', style: theme.textTheme.labelSmall),
              Text('8 小时', style: theme.textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

/// 时间设置项：显示当前时间（HH:mm），点击弹出时间选择器（精确到分钟）。
class _TimeSettingTile extends StatelessWidget {
  const _TimeSettingTile({
    required this.icon,
    required this.title,
    required this.minute,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final int minute;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SettingsListTile(
      leading: Icon(icon),
      title: title,
      subtitle: formatMinutes(minute),
      trailing: const Icon(Icons.access_time),
      onTap: onTap,
    );
  }
}

/// 弹出时间选择器，选择结果以分钟回调。
Future<void> _pickTime(
  BuildContext context,
  TimetableProvider provider, {
  required int initialMinute,
  required ValueChanged<int> onPicked,
}) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(
      hour: initialMinute ~/ 60,
      minute: initialMinute % 60,
    ),
    helpText: '选择时间',
    cancelText: '取消',
    confirmText: '确定',
  );
  if (picked == null) return;
  onPicked(picked.hour * 60 + picked.minute);
}

/// 固定时间段设置项：显示名称与起止时间，点击编辑，右侧删除按钮。
class _FixedBlockTile extends StatelessWidget {
  const _FixedBlockTile({
    required this.block,
    required this.onTap,
    required this.onDelete,
  });

  final GeneralFixedBlock block;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SettingsListTile(
      leading: const Icon(Icons.block_outlined),
      title: block.label,
      subtitle:
          '${formatMinutes(block.startMinute)} - ${formatMinutes(block.endMinute)}',
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: '删除',
        onPressed: onDelete,
      ),
      onTap: onTap,
    );
  }
}

/// 添加/编辑固定时间段弹窗：名称输入 + 开始/结束时间选择器。
class _FixedBlockDialog extends StatefulWidget {
  const _FixedBlockDialog({this.initial});

  final GeneralFixedBlock? initial;

  @override
  State<_FixedBlockDialog> createState() => _FixedBlockDialogState();
}

class _FixedBlockDialogState extends State<_FixedBlockDialog> {
  late final TextEditingController _labelController = TextEditingController(
    text: widget.initial?.label ?? '',
  );
  late int _startMinute = widget.initial?.startMinute ?? 12 * 60;
  late int _endMinute = widget.initial?.endMinute ?? 13 * 60;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<int?> _pickDialogTime(int initialMinute) {
    return showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: initialMinute ~/ 60,
        minute: initialMinute % 60,
      ),
      helpText: '选择时间',
      cancelText: '取消',
      confirmText: '确定',
    ).then((picked) => picked == null ? null : picked.hour * 60 + picked.minute);
  }

  Future<void> _pickStart() async {
    final picked = await _pickDialogTime(_startMinute);
    if (picked != null && mounted) {
      setState(() => _startMinute = picked);
    }
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDialogTime(_endMinute);
    if (picked != null && mounted) {
      setState(() => _endMinute = picked);
    }
  }

  void _confirm() {
    if (_endMinute <= _startMinute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('结束时间必须晚于开始时间')),
      );
      return;
    }
    final label = _labelController.text.trim();
    Navigator.of(context).pop(
      GeneralFixedBlock(
        label: label.isEmpty ? '休息' : label,
        startMinute: _startMinute,
        endMinute: _endMinute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '添加时间段' : '编辑时间段'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: '名称（如：午饭）',
              isDense: true,
            ),
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.access_time),
            title: const Text('开始时间'),
            trailing: Text(
              formatMinutes(_startMinute),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            onTap: _pickStart,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.access_time),
            title: const Text('结束时间'),
            trailing: Text(
              formatMinutes(_endMinute),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            onTap: _pickEnd,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _confirm, child: const Text('确定')),
      ],
    );
  }
}

Future<void> _addFixedBlock(
  BuildContext context,
  TimetableProvider provider,
) async {
  final block = await showDialog<GeneralFixedBlock>(
    context: context,
    builder: (_) => const _FixedBlockDialog(),
  );
  if (block == null) return;
  await provider.updateGeneralDisplaySettings(
    fixedBlocks: [...provider.generalFixedBlocks, block],
  );
}

Future<void> _editFixedBlock(
  BuildContext context,
  TimetableProvider provider,
  int index,
) async {
  final current = provider.generalFixedBlocks[index];
  final block = await showDialog<GeneralFixedBlock>(
    context: context,
    builder: (_) => _FixedBlockDialog(initial: current),
  );
  if (block == null) return;
  final updated = [...provider.generalFixedBlocks];
  updated[index] = block;
  await provider.updateGeneralDisplaySettings(fixedBlocks: updated);
}

Future<void> _deleteFixedBlock(
  BuildContext context,
  TimetableProvider provider,
  int index,
) async {
  final updated = [...provider.generalFixedBlocks]..removeAt(index);
  await provider.updateGeneralDisplaySettings(fixedBlocks: updated);
}
