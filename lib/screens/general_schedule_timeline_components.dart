part of 'general_schedule_home_screen.dart';

class _TimelineTimeRailLabel extends StatelessWidget {
  const _TimelineTimeRailLabel({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow.withValues(alpha: 0.72),
        border: Border(
          right: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: FittedBox(fit: BoxFit.scaleDown, child: child),
    );
  }
}

class _AllDayColumn extends StatelessWidget {
  const _AllDayColumn({
    required this.date,
    required this.width,
    required this.occurrences,
    required this.onTap,
  });

  final DateTime date;
  final double width;
  final List<GeneralEventOccurrence> occurrences;
  final ValueChanged<GeneralEventOccurrence> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: occurrences.isEmpty
          ? const SizedBox.shrink()
          : ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: <Widget>[
                for (final occurrence in occurrences.take(2))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: _AllDayChip(
                      occurrence: occurrence,
                      onTap: () => onTap(occurrence),
                    ),
                  ),
                if (occurrences.length > 2)
                  Text(
                    l10n.moreEvents(occurrences.length - 2),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
    );
  }
}

class _AllDayChip extends StatelessWidget {
  const _AllDayChip({required this.occurrence, required this.onTap});

  final GeneralEventOccurrence occurrence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = effectiveGeneralOccurrenceColor(context, occurrence);
    return Material(
      color: color.withAlpha(36),
      borderRadius: BorderRadius.circular(8),
      child: Semantics(
        button: true,
        label: occurrence.event.title,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            child: Text(
              occurrence.event.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _readableColor(color),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridBackground extends StatelessWidget {
  const _GridBackground({
    required this.timeColumnWidth,
    required this.dayWidth,
    required this.dayCount,
    required this.startMinute,
    required this.endMinute,
    required this.gridMinutes,
    required this.hourHeight,
    required this.topOffset,
    this.unitMinutes = 60,
  });

  final double timeColumnWidth;
  final double dayWidth;
  final int dayCount;
  final int startMinute;
  final int endMinute;
  final int gridMinutes;
  final double hourHeight;
  final double topOffset;

  /// 左侧时间刻度的单位（分钟/格）。放大=更小(15/30/45)，缩小=更大(120/180…)。
  final int unitMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final lineColor = colors.outlineVariant.withValues(alpha: 0.56);
    final minorColor = colors.outlineVariant.withValues(alpha: 0.28);
    final timeLabelColor = colors.onSurfaceVariant;
    final gridStep = gridMinutes.clamp(15, 60).toInt();
    final minuteHeight = hourHeight / 60;
    final unit = unitMinutes.clamp(5, 8 * 60).toInt();
    final firstUnit = (startMinute / unit).ceil();
    final lastUnit = (endMinute / unit).floor();
    return Stack(
      children: [
        Positioned.fill(
          right: null,
          child: Container(
            width: timeColumnWidth,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow.withValues(alpha: 0.72),
              border: Border(right: BorderSide(color: lineColor)),
            ),
          ),
        ),
        for (var u = firstUnit; u <= lastUnit; u++)
          Positioned(
            left: timeColumnWidth,
            right: 0,
            top: topOffset + (u * unit - startMinute) * minuteHeight,
            child: Divider(height: 1, color: lineColor),
          ),
        for (var u = firstUnit; u <= lastUnit; u++)
          Positioned(
            left: 0,
            top:
                topOffset + (u * unit - startMinute) * minuteHeight - 9,
            width: timeColumnWidth,
            height: 18,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _unitLabel(u * unit),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: timeLabelColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        for (var minute = startMinute; minute < endMinute; minute += gridStep)
          if (minute % unit != 0)
            Positioned(
              left: timeColumnWidth,
              right: 0,
              top: topOffset + (minute - startMinute) * minuteHeight,
              child: Divider(height: 1, color: minorColor),
            ),
        for (var day = 0; day <= dayCount; day++)
          Positioned(
            top: topOffset,
            bottom: topOffset,
            left: timeColumnWidth + day * dayWidth,
            child: VerticalDivider(width: 1, color: lineColor),
          ),
      ],
    );
  }

  static String _unitLabel(int minute) {
    final h = minute ~/ 60;
    final m = minute % 60;
    if (m == 0) return '${h.toString().padLeft(2, '0')}:00';
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

class _OccurrenceCard extends StatelessWidget {
  const _OccurrenceCard({
    required this.occurrence,
    required this.dense,
    required this.narrow,
    required this.overlapping,
    required this.onTap,
  });

  final GeneralEventOccurrence occurrence;
  final bool dense;
  final bool narrow;
  final bool overlapping;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = effectiveGeneralOccurrenceColor(context, occurrence);
    final fillColor = _timelineOccurrenceFillColor(color, colorScheme);
    final accentColor = _timelineOccurrenceAccentColor(
      color,
      colorScheme,
      fillColor,
    );
    final detailColor = accentColor.withValues(
      alpha: colorScheme.brightness == Brightness.dark ? 0.78 : 0.72,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(narrow ? 7 : 8),
      side: BorderSide(
        color: overlapping
            ? accentColor.withValues(alpha: 0.74)
            : accentColor.withValues(alpha: 0.46),
        width: overlapping ? 1.1 : 0.9,
      ),
    );
    final titleText = occurrence.event.title;
    final titleStyle =
        (narrow ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
            ?.copyWith(
              color: accentColor,
              fontWeight: FontWeight.w700,
              height: narrow ? 1.08 : 1.1,
            );
    final detailStyle = theme.textTheme.labelSmall?.copyWith(
      color: detailColor,
      fontWeight: FontWeight.w600,
      height: 1.05,
    );
    final locationStyle = theme.textTheme.labelSmall?.copyWith(
      color: detailColor,
      height: 1.05,
    );
    return Material(
      key: ValueKey(
        'general-timed-occurrence-'
        '${occurrence.event.id}-${occurrence.start.toIso8601String()}',
      ),
      color: fillColor,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: occurrence.event.title,
        child: InkWell(
          customBorder: shape,
          overlayColor: _timelineOccurrenceOverlayColor(accentColor),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: narrow ? 2 : 7,
              vertical: dense ? 4 : 6,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final title = _TimelineOccurrenceTitleLayout(
                  text: titleText,
                  style: titleStyle,
                  maxWidth: constraints.maxWidth,
                  maxHeight: constraints.maxHeight,
                  textDirection: Directionality.of(context),
                  narrow: narrow,
                );
                final titleWidget = Text(
                  titleText,
                  maxLines: title.maxLines,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  strutStyle: _timelineTitleStrutStyle(titleStyle, narrow),
                  textAlign: TextAlign.start,
                  style: titleStyle,
                );

                if (dense || narrow || !title.showDetails) {
                  // 紧凑/窄屏也显示开始-结束时间。
                  // 格子宽度足够时时间一行展示（如日视图："19:00 - 19:40"）；
                  // 列太窄（如周视图）时分行显示开始/结束时间；
                  // 标题字号不变、单行省略号截断；格子矮时内容超出裁剪，时间始终可见。
                  return Align(
                    alignment: AlignmentDirectional.topStart,
                    child: LayoutBuilder(
                      builder: (context, constraints) => ClipRect(
                        child: OverflowBox(
                          alignment: AlignmentDirectional.topStart,
                          maxHeight: double.infinity,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  titleText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle,
                                ),
                                if (constraints.maxWidth >= 64)
                                  _CompactTimeLine(
                                    text: _formatOccurrenceTime(
                                      context,
                                      occurrence,
                                    ),
                                    style: detailStyle,
                                  )
                                else ...[
                                  _CompactTimeLine(
                                    text: _formatTime(occurrence.start),
                                    style: detailStyle,
                                  ),
                                  _CompactTimeLine(
                                    text: _formatTime(occurrence.end),
                                    style: detailStyle,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                final details = <Widget>[
                  Text(
                    _formatOccurrenceTime(context, occurrence),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: detailStyle,
                  ),
                  if (occurrence.event.location.isNotEmpty)
                    Text(
                      occurrence.event.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: locationStyle,
                    ),
                ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleWidget,
                    const SizedBox(height: 2),
                    ...details,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 可长按拖拽的课程卡片：仅 LinkStudy 课程事件启用。
/// 长按后上下拖动调整开始时间（吸附到网格粒度）、左右拖动跨天；
/// 拖动中卡片实时跟随，松手后把目标日期/时间通过 [onMoveCourse] 抛出。
class _DraggableOccurrenceCard extends StatefulWidget {
  const _DraggableOccurrenceCard({
    required this.occurrence,
    required this.dense,
    required this.narrow,
    required this.overlapping,
    required this.onTap,
    required this.draggable,
    required this.startMinutes,
    required this.endMinutes,
    required this.minuteHeight,
    required this.dayIndex,
    required this.onMoveCourse,
  });

  final GeneralEventOccurrence occurrence;
  final bool dense;
  final bool narrow;
  final bool overlapping;
  final VoidCallback onTap;
  final bool draggable;
  final int startMinutes;
  final int endMinutes;
  final double minuteHeight;
  final int dayIndex;

  /// 参数：目标日下标 / 目标开始分钟 / 相对原始开始分钟的偏移。
  final void Function(int dayIndex, int startMinute, int deltaMinutes)
  onMoveCourse;

  @override
  State<_DraggableOccurrenceCard> createState() =>
      _DraggableOccurrenceCardState();
}

class _DraggableOccurrenceCardState extends State<_DraggableOccurrenceCard> {
  Offset _dragOffset = Offset.zero;
  bool _dragging = false;
  int _originalStartMinute = 0;
  int _originalDayIndex = 0;

  @override
  Widget build(BuildContext context) {
    final card = _OccurrenceCard(
      occurrence: widget.occurrence,
      dense: widget.dense,
      narrow: widget.narrow,
      overlapping: widget.overlapping,
      onTap: widget.onTap,
    );
    if (!widget.draggable) return card;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (details) {
        _originalStartMinute = widget.occurrence.start.hour * 60 +
            widget.occurrence.start.minute;
        _originalDayIndex = widget.dayIndex;
        HapticFeedback.mediumImpact();
        setState(() {
          _dragging = true;
          _dragOffset = Offset.zero;
        });
      },
      onLongPressMoveUpdate: (details) {
        if (!_dragging) return;
        setState(() {
          _dragOffset = details.offsetFromOrigin;
        });
      },
      onLongPressEnd: (details) {
        if (!_dragging) return;
        final rawMinutes = (_dragOffset.dy / widget.minuteHeight).round();
        // 按 1 分钟精确跟随，避免小距离拖动被吸附回原位。
        final deltaMinutes = rawMinutes;
        final newStart = (_originalStartMinute + deltaMinutes)
            .clamp(widget.startMinutes, widget.endMinutes - 15);
        // 跨天：每超过一个 dayWidth 算一天。
        final dayShift = (_dragOffset.dx / 80).round();
        final newDayIndex = _originalDayIndex + dayShift;
        setState(() {
          _dragging = false;
          _dragOffset = Offset.zero;
        });
        widget.onMoveCourse(newDayIndex, newStart, deltaMinutes);
      },
      onLongPressCancel: () {
        if (!_dragging) return;
        setState(() {
          _dragging = false;
          _dragOffset = Offset.zero;
        });
      },
      child: Transform.translate(
        offset: _dragOffset,
        child: card,
      ),
    );
  }
}

class _MoreOccurrencesCard extends StatelessWidget {
  const _MoreOccurrencesCard({
    required this.occurrence,
    required this.count,
    required this.dense,
    required this.narrow,
    required this.overlapping,
    required this.onTap,
  });

  final GeneralEventOccurrence occurrence;
  final int count;
  final bool dense;
  final bool narrow;
  final bool overlapping;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final color = effectiveGeneralOccurrenceColor(context, occurrence);
    final fillColor = _timelineOccurrenceFillColor(color, colorScheme);
    final accentColor = _timelineOccurrenceAccentColor(
      color,
      colorScheme,
      fillColor,
    );
    final label = l10n.moreEvents(count);
    final visualLabel = narrow ? '+$count' : label;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(narrow ? 7 : 8),
      side: BorderSide(
        color: accentColor.withValues(alpha: overlapping ? 0.70 : 0.50),
        width: overlapping ? 1.1 : 0.9,
      ),
    );
    final text = Text(
      visualLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      textAlign: TextAlign.center,
      style: (narrow ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)
          ?.copyWith(
            color: accentColor,
            fontWeight: FontWeight.w800,
            height: 1.08,
          ),
    );

    return Material(
      key: ValueKey(
        'general-timed-more-occurrences-'
        '${occurrence.event.id}-${occurrence.start.toIso8601String()}',
      ),
      color: fillColor,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          customBorder: shape,
          overlayColor: _timelineOccurrenceOverlayColor(accentColor),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: narrow ? 2 : 7,
              vertical: dense ? 4 : 6,
            ),
            child: Center(
              child: narrow
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 1),
                        child: text,
                      ),
                    )
                  : text,
            ),
          ),
        ),
      ),
    );
  }
}

StrutStyle? _timelineTitleStrutStyle(TextStyle? style, bool narrow) {
  final fontSize = style?.fontSize;
  if (fontSize == null) {
    return null;
  }
  return StrutStyle(
    fontSize: fontSize,
    height: narrow ? 1.04 : 1.06,
    forceStrutHeight: true,
  );
}

class _TimelineOccurrenceTitleLayout {
  _TimelineOccurrenceTitleLayout({
    required String text,
    required TextStyle? style,
    required double maxWidth,
    required double maxHeight,
    required TextDirection textDirection,
    required bool narrow,
  }) {
    final safeWidth = maxWidth.isFinite && maxWidth > 0 ? maxWidth : 1.0;
    final safeHeight = maxHeight.isFinite && maxHeight > 0 ? maxHeight : 28.0;
    final fontSize = style?.fontSize ?? 12.0;
    final lineHeight = fontSize * (style?.height ?? 1.15);
    final possibleLines = math.max(1, (safeHeight / lineHeight).floor());
    final cappedPossibleLines = possibleLines.clamp(1, narrow ? 10 : 5).toInt();

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      maxLines: 8,
    )..layout(maxWidth: safeWidth);
    final neededLines = math.max(1, painter.computeLineMetrics().length);
    final titleFits = neededLines <= cappedPossibleLines;
    final detailsHeight = lineHeight + 4;

    maxLines = titleFits ? neededLines : cappedPossibleLines;
    showDetails =
        !narrow &&
        titleFits &&
        neededLines <= 2 &&
        safeWidth >= 64 &&
        safeHeight >= neededLines * lineHeight + detailsHeight;
  }

  late final int maxLines;
  late final bool showDetails;
}

Color _timelineOccurrenceFillColor(Color color, ColorScheme colorScheme) {
  final surface = colorScheme.brightness == Brightness.dark
      ? colorScheme.surfaceContainerHigh
      : colorScheme.surfaceContainerLow;
  final alpha = colorScheme.brightness == Brightness.dark ? 0.20 : 0.10;
  return Color.alphaBlend(color.withValues(alpha: alpha), surface);
}

Color _timelineOccurrenceAccentColor(
  Color color,
  ColorScheme colorScheme,
  Color fillColor,
) {
  var candidate = color.withValues(alpha: 1);
  if (_contrastRatio(candidate, fillColor) >= 3.0) {
    return candidate;
  }

  final target = colorScheme.brightness == Brightness.dark
      ? Colors.white
      : Colors.black;
  for (final alpha in const [0.18, 0.32, 0.46, 0.60]) {
    candidate = Color.alphaBlend(target.withValues(alpha: alpha), color);
    if (_contrastRatio(candidate, fillColor) >= 3.0) {
      return candidate;
    }
  }
  return colorScheme.brightness == Brightness.dark
      ? colorScheme.primaryContainer
      : colorScheme.primary;
}

WidgetStateProperty<Color?> _timelineOccurrenceOverlayColor(Color accentColor) {
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.pressed)) {
      return accentColor.withValues(alpha: 0.18);
    }
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused)) {
      return accentColor.withValues(alpha: 0.12);
    }
    return null;
  });
}

double _contrastRatio(Color a, Color b) {
  final aLuminance = a.computeLuminance();
  final bLuminance = b.computeLuminance();
  final lighter = math.max(aLuminance, bLuminance);
  final darker = math.min(aLuminance, bLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

/// 紧凑时间行：小字号（10px），列太窄时缩放保证完整显示（不截断）。
class _CompactTimeLine extends StatelessWidget {
  const _CompactTimeLine({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        maxLines: 1,
        style: style?.copyWith(fontSize: 10, height: 1.1),
      ),
    );
  }
}
