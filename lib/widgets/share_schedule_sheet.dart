import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/general_models.dart';
import '../providers/timetable_provider.dart';
import '../utils/general_schedule_colors.dart';
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

  /// 7 天范围的起始日期（默认今天）。
  DateTime _startDate = normalizeDateOnly(DateTime.now());

  String get _rangeLabel => switch (_range) {
    _ShareRange.today => '当天日程',
    _ShareRange.week7 => '${_dateLabel(_startDate)}起 7 天日程',
  };

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _startDate = normalizeDateOnly(picked));
    }
  }

  static String _dateLabel(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<GeneralEventOccurrence> get _occurrences {
    final provider = widget.provider;
    final start = normalizeDateOnly(
      _range == _ShareRange.today ? provider.selectedGeneralDate : _startDate,
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
      if (_range == _ShareRange.week7) 'startDate': _dateLabel(_startDate),
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
    // 确定要展示的每一天：当天 1 天 / 7 天范围全部 7 天（无课程的日期也展示）。
    final start = normalizeDateOnly(
      _range == _ShareRange.today
          ? widget.provider.selectedGeneralDate
          : _startDate,
    );
    final dayCount = _range == _ShareRange.today ? 1 : 7;
    final days = [
      for (var i = 0; i < dayCount; i++) start.add(Duration(days: i)),
    ];
    // 渲染海报 → 截图 → 存临时文件 → 分享图片。
    // 海报是固定设计稿：不受系统字体缩放影响，避免小格子文字溢出。
    final boundaryKey = GlobalKey();
    final poster = RepaintBoundary(
      key: boundaryKey,
      child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.noScaling),
        child: SchedulePoster(days: days, occurrences: list),
      ),
    );
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -20000,
        top: -20000,
        width: 50000,
        height: 50000,
        child: IgnorePointer(
          // 海报在超大离屏区域内按自然尺寸布局（可宽于屏幕），
          // 截图完整捕获整张海报，且不会触发溢出异常。
          child: UnconstrainedBox(
            alignment: Alignment.topLeft,
            child: poster,
          ),
        ),
      ),
    );
    overlay.insert(entry);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
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
          if (_range == _ShareRange.week7) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickStartDate,
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Text('开始日期：${_dateLabel(_startDate)}'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
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

/// 学习课表分享海报：柔和蓝白渐变底 + 居中半透明白色圆角大卡片，
/// 卡片内是真正的课程表：左侧时间刻度 × 顶部星期/日期，课程按时间
/// 放进格子，7 天横向并排（无课程的日期也展示），右下角水印。
/// 画布宽度按天数横向撑开、高度按时间跨度自适应，与屏幕尺寸无关。
class SchedulePoster extends StatelessWidget {
  const SchedulePoster({super.key, required this.days, required this.occurrences});

  /// 要展示的每一天（含无课程的日子）。
  final List<DateTime> days;
  final List<GeneralEventOccurrence> occurrences;

  // 画布尺寸（逻辑像素）。
  static const _edgeMargin = 80.0;
  static const _topBottomMargin = 120.0;
  static const _cardRadius = 28.0;
  static const _cardPadding = 48.0;

  // 配色。
  static const _ink = Color(0xFF222222);
  static const _subtitleColor = Color(0xFF707070);
  static const _watermarkColor = Color(0xFF909090);

  static const _weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  Widget build(BuildContext context) {
    // 按日期分组并按开始时间排序。
    final byDay = <String, List<GeneralEventOccurrence>>{};
    for (final o in occurrences) {
      byDay.putIfAbsent(_dateKey(o.start), () => []).add(o);
    }
    for (final l in byDay.values) {
      l.sort((a, b) => a.start.compareTo(b.start));
    }

    // 时间范围：覆盖最早开始 ~ 最晚结束（取整到小时），最小跨度 4 小时。
    var minMinute = 6 * 60;
    var maxMinute = 23 * 60;
    if (occurrences.isNotEmpty) {
      var minStart = occurrences.first.start.hour * 60 + occurrences.first.start.minute;
      var maxEnd = occurrences.first.end.hour * 60 + occurrences.first.end.minute;
      for (final o in occurrences) {
        final s = o.start.hour * 60 + o.start.minute;
        final e = o.end.hour * 60 + o.end.minute;
        if (s < minStart) minStart = s;
        if (e > maxEnd) maxEnd = e;
      }
      minMinute = minStart ~/ 60 * 60;
      maxMinute = ((maxEnd + 59) ~/ 60) * 60;
      if (maxMinute - minMinute < 4 * 60) {
        maxMinute = minMinute + 4 * 60;
      }
      if (minMinute < 0) minMinute = 0;
      if (maxMinute > 24 * 60) maxMinute = 24 * 60;
    }

    // 横版海报：宽度按天数横向撑开，高度按内容自适应。
    final posterWidth =
        2 * _edgeMargin +
        2 * _cardPadding +
        _TimetableGrid.timeColWidth +
        days.length * _TimetableGrid.dayColWidth;

    return Container(
      width: posterWidth,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDCE9FF), Color(0xFFF5F8FF), Color(0xFFEAF3FF)],
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: _edgeMargin,
        vertical: _topBottomMargin,
      ),
      child: Container(
        padding: const EdgeInsets.all(_cardPadding),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(_cardRadius),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C93C9).withValues(alpha: 0.28),
              blurRadius: 40,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 顶部主标题 + 副标题。
            const Text(
              '我的日程',
              style: TextStyle(
                color: _ink,
                fontSize: 60,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'AI智能规划网课日程',
              style: TextStyle(
                color: _subtitleColor,
                fontSize: 32,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 56),
            // 2. 课程表（时间 × 星期网格）。
            _TimetableGrid(
              days: days,
              byDay: byDay,
              minMinute: minMinute,
              maxMinute: maxMinute,
            ),
            // 3. 底部大片留白 + 右下角水印。
            const SizedBox(height: 110),
            Align(
              alignment: Alignment.centerRight,
              child: Opacity(
                opacity: 0.6,
                child: const Text(
                  '由LinkStudy生成',
                  style: TextStyle(
                    color: _watermarkColor,
                    fontSize: 26,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _hourLabel(int minute) {
    final h = minute ~/ 60;
    return '${h.toString().padLeft(2, '0')}:00';
  }

  static String _hhmmText(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// 课程表网格：左侧时间刻度 × 顶部星期/日期，课程块按时间绝对定位。
class _TimetableGrid extends StatelessWidget {
  const _TimetableGrid({
    required this.days,
    required this.byDay,
    required this.minMinute,
    required this.maxMinute,
  });

  final List<DateTime> days;
  final Map<String, List<GeneralEventOccurrence>> byDay;
  final int minMinute;
  final int maxMinute;

  // 网格参数：单格宽高比 1.5:1（300 × 200）。
  static const timeColWidth = 100.0;
  static const dayColWidth = 300.0;
  static const hourHeight = 200.0;
  static const headerHeight = 96.0;

  @override
  Widget build(BuildContext context) {
    final hourCount = (maxMinute - minMinute) ~/ 60;
    final gridHeight = hourCount * hourHeight;
    final tableWidth = timeColWidth + days.length * dayColWidth;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 表头：时间 + 星期/日期。
          SizedBox(
            height: headerHeight,
            child: Row(
              children: [
                Container(
                  width: timeColWidth,
                  color: const Color(0xFFF0F2F8),
                  alignment: Alignment.center,
                  child: const Text(
                    '时间',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
                for (final d in days)
                  Container(
                    width: dayColWidth,
                    color: const Color(0xFFF0F2F8),
                    alignment: Alignment.center,
                    // FittedBox 兜底：字体放大时内容整体缩放，不会溢出表头。
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            SchedulePoster._weekdayNames[d.weekday - 1],
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2A2F3A),
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${d.month}月${d.day}日',
                            style: const TextStyle(
                              fontSize: 24,
                              color: Color(0xFF9AA0AE),
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 网格主体。
          SizedBox(
            width: tableWidth,
            height: gridHeight,
            child: Stack(
              children: [
                // 背景行线 + 时间刻度。
                for (var h = 0; h < hourCount; h++)
                  Positioned(
                    left: 0,
                    top: h * hourHeight,
                    right: 0,
                    child: Row(
                      children: [
                        SizedBox(
                          width: timeColWidth,
                          height: hourHeight,
                          child: Container(
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFAFBFD),
                              border: Border(
                                bottom: BorderSide(color: Color(0xFFE8EAF2)),
                              ),
                            ),
                            child: Text(
                              SchedulePoster._hourLabel(minMinute + h * 60),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9AA0AE),
                              ),
                            ),
                          ),
                        ),
                        for (var d = 0; d < days.length; d++)
                          Container(
                            width: dayColWidth,
                            height: hourHeight,
                            decoration: const BoxDecoration(
                              border: Border(
                                right: BorderSide(color: Color(0xFFEDEFF5)),
                                bottom: BorderSide(color: Color(0xFFEDEFF5)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                // 课程块（按时间绝对定位，颜色与软件内课程一致）。
                for (var d = 0; d < days.length; d++)
                  for (final o in byDay[SchedulePoster._dateKey(days[d])] ??
                      const <GeneralEventOccurrence>[])
                    _courseBlock(
                      occurrence: o,
                      color: effectiveGeneralOccurrenceColor(context, o),
                      left: timeColWidth + d * dayColWidth,
                      top:
                          (o.start.hour * 60 + o.start.minute - minMinute) /
                          60.0 *
                          hourHeight,
                      height:
                          o.end.difference(o.start).inMinutes / 60.0 * hourHeight,
                      width: dayColWidth,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 单条课程块：与周视图一致的玻璃效果（课程色低透明度填充 +
  /// 细微加粗的 accent 描边 + accent 文字），格子太矮时只显示标题。
  Widget _courseBlock({
    required GeneralEventOccurrence occurrence,
    required Color color,
    required double left,
    required double top,
    required double height,
    required double width,
  }) {
    // 格子高度过小时补足到最小高度。
    final cellHeight = (height - 6).clamp(40.0, double.infinity);
    final titleLines = cellHeight >= 96 ? 2 : 1;
    final fill = _glassFillColor(color);
    final accent = _glassAccentColor(color, fill);
    final detail = accent.withValues(alpha: 0.72);
    return Positioned(
      left: left + 4,
      top: top + 3,
      width: width - 8,
      height: cellHeight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: accent.withValues(alpha: 0.50),
            width: 1.6,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        // 内容高度不受格子限制（不触发溢出报错），超出部分按格子裁剪。
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxHeight: double.infinity,
          child: SizedBox(
            width: width - 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  occurrence.event.title,
                  maxLines: titleLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${SchedulePoster._hhmmText(occurrence.start)}-'
                  '${SchedulePoster._hhmmText(occurrence.end)}',
                  style: TextStyle(
                    fontSize: 18,
                    color: detail,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// —— 与周视图课程格一致的“玻璃”配色（海报为浅色底，按亮色处理） ——

Color _glassFillColor(Color color) =>
    Color.alphaBlend(color.withValues(alpha: 0.10), Colors.white);

Color _glassAccentColor(Color color, Color fill) {
  var candidate = color.withValues(alpha: 1);
  if (_contrastRatio(candidate, fill) >= 3.0) {
    return candidate;
  }
  for (final alpha in const [0.18, 0.32, 0.46, 0.60]) {
    candidate = Color.alphaBlend(Colors.black.withValues(alpha: alpha), color);
    if (_contrastRatio(candidate, fill) >= 3.0) {
      return candidate;
    }
  }
  return const Color(0xFF4D6BFE);
}

double _contrastRatio(Color a, Color b) {
  final aLuminance = a.computeLuminance();
  final bLuminance = b.computeLuminance();
  final lighter = math.max(aLuminance, bLuminance);
  final darker = math.min(aLuminance, bLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}
