import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/general_models.dart';
import '../providers/timetable_provider.dart';
import 'app_modal_sheet.dart';

/// 分享日程弹窗：选择范围（当天 / 未来 7 天）与格式（图片 / Markdown / JSON / 纯文字）。
Future<void> showShareScheduleSheet(
  BuildContext context, {
  required TimetableProvider provider,
}) {
  return showAppModalSheet<void>(
    context: context,
    maxWidth: appSheetWidthMedium,
    builder: (sheetContext) => _ShareScheduleSheet(provider: provider),
  );
}

enum _ShareRange { today, week7 }

enum _ShareFormat { image, markdown, json, text }

class _ShareScheduleSheet extends StatefulWidget {
  const _ShareScheduleSheet({required this.provider});

  final TimetableProvider provider;

  @override
  State<_ShareScheduleSheet> createState() => _ShareScheduleSheetState();
}

class _ShareScheduleSheetState extends State<_ShareScheduleSheet> {
  _ShareRange _range = _ShareRange.today;
  _ShareFormat _format = _ShareFormat.image;

  String get _rangeLabel => switch (_range) {
    _ShareRange.today => '当天日程',
    _ShareRange.week7 => '未来 7 天日程',
  };

  List<GeneralEventOccurrence> get _occurrences {
    final provider = widget.provider;
    final start = normalizeDateOnly(
      _range == _ShareRange.today
          ? provider.selectedGeneralDate
          : DateTime.now(),
    );
    final end = start.add(Duration(days: _range == _ShareRange.today ? 1 : 7));
    return provider.generalOccurrencesForRange(
      startInclusive: start,
      endExclusive: end,
    );
  }

  Future<void> _share() async {
    final occurrences = _occurrences;
    switch (_format) {
      case _ShareFormat.text:
        await _shareText(occurrences);
      case _ShareFormat.markdown:
        await _shareMarkdown(occurrences);
      case _ShareFormat.json:
        await _shareJson(occurrences);
      case _ShareFormat.image:
        await _shareImage(occurrences);
    }
  }

  Future<void> _shareText(List<GeneralEventOccurrence> list) async {
    if (list.isEmpty) {
      _toast('$_rangeLabel为空，没有可分享的内容');
      return;
    }
    final lines = [
      for (final o in list)
        '${_dayLabel(o)} ${_hhmm(o.start)}-${_hhmm(o.end)} ${o.event.title}',
    ];
    await SharePlus.instance.share(
      ShareParams(text: '$_rangeLabel\n${lines.join('\n')}'),
    );
  }

  Future<void> _shareMarkdown(List<GeneralEventOccurrence> list) async {
    if (list.isEmpty) {
      _toast('$_rangeLabel为空，没有可分享的内容');
      return;
    }
    final buffer = StringBuffer('# $_rangeLabel\n\n');
    for (final o in list) {
      buffer.writeln(
        '- **${_dayLabel(o)}** ${_hhmm(o.start)}-${_hhmm(o.end)} — ${o.event.title}',
      );
    }
    await SharePlus.instance.share(ShareParams(text: buffer.toString()));
  }

  Future<void> _shareJson(List<GeneralEventOccurrence> list) async {
    if (list.isEmpty) {
      _toast('$_rangeLabel为空，没有可分享的内容');
      return;
    }
    final data = {
      'range': _range == _ShareRange.today ? 'today' : '7days',
      'events': [
        for (final o in list)
          {
            'date': o.start.toIso8601String().split('T').first,
            'start': _hhmm(o.start),
            'end': _hhmm(o.end),
            'title': o.event.title,
            'location': o.event.location,
          },
      ],
    };
    final text = const JsonEncoder.withIndent('  ').convert(data);
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _shareImage(List<GeneralEventOccurrence> list) async {
    if (list.isEmpty) {
      _toast('$_rangeLabel为空，没有可分享的内容');
      return;
    }
    // 渲染精美海报 → 截图 → 存临时文件 → 分享图片。
    final boundaryKey = GlobalKey();
    final poster = RepaintBoundary(
      key: boundaryKey,
      child: _SchedulePoster(rangeLabel: _rangeLabel, occurrences: list),
    );
    // 先挂载到 Overlay 渲染一帧再截图。
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(builder: (_) => poster);
    overlay.insert(entry);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _toast('图片生成失败');
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/schedule_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: '我的$_rangeLabel',
        ),
      );
    } catch (e) {
      _toast('图片分享失败：$e');
    } finally {
      entry.remove();
    }
  }

  String _dayLabel(GeneralEventOccurrence o) {
    final d = o.start;
    return '${d.month}月${d.day}日 ${_weekday(d.weekday)}';
  }

  static String _weekday(int weekday) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSheetScaffold(
      heightFactor: 0.62,
      title: const Text('分享日程'),
      subtitle: const Text('选择范围与格式，分享你的学习日程'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _share, child: const Text('分享')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('范围', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<_ShareRange>(
            segments: const [
              ButtonSegment(
                value: _ShareRange.today,
                icon: Icon(Icons.today_outlined),
                label: Text('当天'),
              ),
              ButtonSegment(
                value: _ShareRange.week7,
                icon: Icon(Icons.calendar_view_week_outlined),
                label: Text('7 天'),
              ),
            ],
            selected: {_range},
            onSelectionChanged: (s) => setState(() => _range = s.first),
          ),
          const SizedBox(height: 16),
          Text('格式', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FormatChip(
                icon: Icons.image_outlined,
                label: '图片',
                selected: _format == _ShareFormat.image,
                onTap: () => setState(() => _format = _ShareFormat.image),
              ),
              _FormatChip(
                icon: Icons.notes_outlined,
                label: 'Markdown',
                selected: _format == _ShareFormat.markdown,
                onTap: () => setState(() => _format = _ShareFormat.markdown),
              ),
              _FormatChip(
                icon: Icons.data_object_outlined,
                label: 'JSON',
                selected: _format == _ShareFormat.json,
                onTap: () => setState(() => _format = _ShareFormat.json),
              ),
              _FormatChip(
                icon: Icons.text_fields_outlined,
                label: '纯文字',
                selected: _format == _ShareFormat.text,
                onTap: () => setState(() => _format = _ShareFormat.text),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '共 ${_occurrences.length} 条日程',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.14)
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colors.primary : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? colors.primary : null),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: selected ? colors.primary : null,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 精美日程海报（图片分享渲染用）。
class _SchedulePoster extends StatelessWidget {
  const _SchedulePoster({required this.rangeLabel, required this.occurrences});

  final String rangeLabel;
  final List<GeneralEventOccurrence> occurrences;

  static const _colors = [
    Color(0xFF4D6BFE),
    Color(0xFF22A06B),
    Color(0xFFE8590C),
    Color(0xFF9C36B5),
    Color(0xFF0CA678),
    Color(0xFFE64980),
  ];

  @override
  Widget build(BuildContext context) {
    // 按日期分组。
    final byDay = <String, List<GeneralEventOccurrence>>{};
    for (final o in occurrences) {
      final key = o.start.toIso8601String().split('T').first;
      byDay.putIfAbsent(key, () => []).add(o);
    }
    final days = byDay.keys.toList()..sort();
    final total = occurrences.length;

    return Material(
      color: const Color(0xFFF6F7FB),
      child: Container(
        width: 720,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部渐变标题。
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4D6BFE), Color(0xFF7C5CFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📅 $rangeLabel',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '共 $total 条日程 · LinkStudy',
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < days.length; i++) ...[
              _DaySection(
                dayKey: days[i],
                items: byDay[days[i]]!,
                color: _colors[i % _colors.length],
              ),
              if (i < days.length - 1) const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.dayKey,
    required this.items,
    required this.color,
  });

  final String dayKey;
  final List<GeneralEventOccurrence> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(dayKey);
    final weekday = date == null
        ? ''
        : const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][date.weekday - 1];
    final monthDay = date == null ? dayKey : '${date.month}月${date.day}日';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$monthDay $weekday',
                style: TextStyle(
                  color: color,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${items.length} 条',
                style: const TextStyle(color: Color(0xFF9AA0AE), fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final o in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_hhmm(o.start)}-${_hhmm(o.end)}',
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      o.event.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2A2F3A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
