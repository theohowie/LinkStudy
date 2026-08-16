import 'package:flutter/material.dart';

import '../providers/timetable_provider.dart';
import 'app_modal_sheet.dart';

/// 时间精度调节半弹窗（很矮）：滑块无级调节 5-480 分钟/刻度，也可输入数字。
/// 修改后实时写入通用显示设置，周视图时间刻度立即生效。
Future<void> showTimelinePrecisionSheet(
  BuildContext context, {
  required TimetableProvider provider,
}) {
  return showAppModalSheet<void>(
    context: context,
    maxWidth: appSheetWidthCompact,
    isDismissible: true,
    enableDrag: true,
    builder: (sheetContext) => _TimelinePrecisionSheet(provider: provider),
  );
}

class _TimelinePrecisionSheet extends StatefulWidget {
  const _TimelinePrecisionSheet({required this.provider});

  final TimetableProvider provider;

  @override
  State<_TimelinePrecisionSheet> createState() =>
      _TimelinePrecisionSheetState();
}

class _TimelinePrecisionSheetState extends State<_TimelinePrecisionSheet> {
  late int _value = widget.provider.generalTimelineUnitMinutes;
  late final TextEditingController _controller = TextEditingController(
    text: '$_value',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      setState(() => _controller.text = '$_value');
      return;
    }
    final clamped = parsed.clamp(5, 480);
    setState(() {
      _value = clamped;
      _controller.text = '$clamped';
    });
    widget.provider.updateGeneralDisplaySettings(timelineUnitMinutes: clamped);
  }

  void _setValue(int v) {
    final clamped = v.clamp(5, 480);
    setState(() {
      _value = clamped;
      _controller.text = '$clamped';
    });
    widget.provider.updateGeneralDisplaySettings(timelineUnitMinutes: clamped);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (_value) {
      <= 60 => '${_value} 分钟/格（放大）',
      < 480 => '${_value} 分钟/格（≈${(_value / 60).toStringAsFixed(1)} 小时）',
      _ => '8 小时/格（缩小到最大）',
    };
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.zoom_in_map_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '时间精度',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 92,
                  height: 34,
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                      border: OutlineInputBorder(),
                      suffixText: '分',
                      suffixStyle: TextStyle(fontSize: 12),
                    ),
                    onSubmitted: (_) => _commit(),
                    onEditingComplete: _commit,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Slider(
              value: _value.toDouble(),
              min: 5,
              max: 480,
              divisions: 475,
              label: '$_value 分钟',
              onChanged: (v) => _setValue(v.round()),
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
      ),
    );
  }
}
