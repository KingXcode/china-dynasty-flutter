import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import 'history.dart';

const _palette = <Color>[
  Color(0xffa2573d),
  Color(0xff547b67),
  Color(0xff8e7b9f),
  Color(0xff527d91),
  Color(0xffae9453),
  Color(0xff6b8c80),
  Color(0xffb67870),
  Color(0xff77864d),
  Color(0xff5c759d),
  Color(0xffa58a77),
  Color(0xff7c8a90),
  Color(0xffae7250),
];
const _ink = Color(0xff24262b);
const _secondary = Color(0xff797b83);
const _separator = Color(0xffe9e9ed);

int _yearFromOrdinal(int value) => value <= 0 ? value - 1 : value;

/// A globally shared compression band, containing no start or end events.
/// Existing periods can cross the band; their durations are not changed.
class DesktopTimelineFold {
  const DesktopTimelineFold(this.start, this.end);
  final int start;
  final int end;
  static const double height = 38;
}

/// Date geometry is independent of label geometry. No historical year zero is
/// inserted, including when a compression band crosses the BCE / CE boundary.
class DesktopTimelineScale {
  DesktopTimelineScale({
    required this.start,
    required this.end,
    required List<Map<String, dynamic>> records,
    required bool exact,
    required double zoom,
    double labelSpace = 54,
  }) {
    final range = math.max(1, yearSpan(start, end));
    pixelsPerYear =
        (range > 900 ? 1.25 : (650 / range).clamp(2.0, 8.0)) *
        zoom.clamp(.25, 4.0);
    if (!exact) {
      final events = <int>{start, end};
      for (final record in records) {
        events
          ..add((record['start'] as int).clamp(start, end))
          ..add((record['end'] as int).clamp(start, end));
      }
      final sorted = events.toList()..sort();
      // Keep room for a legible label before each fold, even when zoomed out.
      final shoulder = math.max(45, ((labelSpace + 4) / pixelsPerYear).ceil());
      for (var i = 1; i < sorted.length; i++) {
        final gap = yearSpan(sorted[i - 1], sorted[i]);
        if (gap > math.max(220, shoulder * 2 + 60)) {
          folds.add(
            DesktopTimelineFold(
              _yearFromOrdinal(ordinal(sorted[i - 1]) + shoulder),
              _yearFromOrdinal(ordinal(sorted[i]) - shoulder),
            ),
          );
        }
      }
    }
  }

  final int start;
  final int end;
  late final double pixelsPerYear;
  final List<DesktopTimelineFold> folds = [];
  static const double top = 64;

  double y(int year) {
    var result = yearSpan(start, year) * pixelsPerYear;
    for (final fold in folds) {
      if (year <= fold.start) break;
      final covered = yearSpan(fold.start, math.min(year, fold.end));
      final total = yearSpan(fold.start, fold.end);
      result -=
          covered * pixelsPerYear -
          covered / total * DesktopTimelineFold.height;
    }
    return top + result;
  }

  List<int> get ticks {
    final range = yearSpan(start, end);
    final step = range > 2500
        ? 200
        : range > 900
        ? 100
        : range > 300
        ? 50
        : range > 100
        ? 20
        : range > 30
        ? 10
        : 1;
    final candidates = <int>{start, end};
    for (var year = (start / step).ceil() * step; year < end; year += step) {
      if (year != 0) candidates.add(year);
    }
    if (start < 1 && end > 1) candidates.add(1);
    final result = <int>[];
    for (final year in candidates.toList()..sort()) {
      if (folds.any((fold) => year > fold.start && year < fold.end)) continue;
      if (result.isEmpty || y(year) - y(result.last) >= 27) result.add(year);
    }
    return result;
  }
}

class DesktopTimelineEntry {
  const DesktopTimelineEntry({
    required this.record,
    required this.lane,
    required this.startY,
    required this.endY,
    required this.continuesBefore,
    required this.continuesAfter,
    required this.color,
    this.labelSpace = 54,
  });
  final Map<String, dynamic> record;
  final int lane;
  final double startY;
  final double endY;
  final bool continuesBefore;
  final bool continuesAfter;
  final Color color;
  final double labelSpace;
  double get x =>
      DesktopTimelineLayout.axisWidth + lane * DesktopTimelineLayout.laneWidth;
  double get reservedUntil => math.max(endY, startY + labelSpace);
}

/// Greedy track packing reserves both real duration and readable label space.
/// Lane widths never expand to fill desktop screens.
class DesktopTimelineLayout {
  DesktopTimelineLayout({
    required List<Map<String, dynamic>> records,
    required List<Map<String, dynamic>> allRecords,
    required bool exact,
    required double zoom,
    int? start,
    int? end,
    double labelSpace = labelReservation,
  }) {
    final valid = records.where((record) {
      final a = record['start'];
      final b = record['end'];
      return a is int && b is int && a != 0 && b != 0 && a <= b;
    }).toList();
    this.start =
        start ??
        (valid.isEmpty
            ? 1
            : valid.map((r) => r['start'] as int).reduce(math.min));
    this.end =
        end ??
        (valid.isEmpty
            ? 2
            : valid.map((r) => r['end'] as int).reduce(math.max));
    assert(this.start != 0 && this.end != 0 && this.start <= this.end);
    final visible =
        valid
            .where(
              (record) =>
                  (record['start'] as int) <= this.end &&
                  (record['end'] as int) >= this.start,
            )
            .toList()
          ..sort((a, b) {
            final date = (a['start'] as int).compareTo(b['start'] as int);
            if (date != 0) return date;
            final core = (b['core'] == true ? 1 : 0).compareTo(
              a['core'] == true ? 1 : 0,
            );
            if (core != 0) return core;
            return (b['end'] as int).compareTo(a['end'] as int);
          });
    scale = DesktopTimelineScale(
      start: this.start,
      end: this.end,
      records: visible,
      exact: exact,
      zoom: zoom,
      labelSpace: labelSpace,
    );
    final reserved = <double>[];
    for (final record in visible) {
      final a = record['start'] as int;
      final b = record['end'] as int;
      final startY = scale.y(math.max(this.start, a));
      final endY = scale.y(math.min(this.end, b));
      var lane = reserved.indexWhere((bottom) => bottom <= startY + .00001);
      if (lane < 0) {
        lane = reserved.length;
        reserved.add(0);
      }
      final originalIndex = allRecords.indexWhere(
        (r) => r['id'] == record['id'],
      );
      final hex = (record['color'] as String?)?.replaceFirst('#', '');
      final customColor = hex != null && hex.length == 6
          ? int.tryParse(hex, radix: 16)
          : null;
      final entry = DesktopTimelineEntry(
        record: record,
        labelSpace: labelSpace,
        lane: lane,
        startY: startY,
        endY: endY,
        continuesBefore: a < this.start,
        continuesAfter: b > this.end,
        color: customColor == null
            ? _palette[math.max(0, originalIndex) % _palette.length]
            : Color(0xff000000 | customColor),
      );
      entries.add(entry);
      reserved[lane] = entry.reservedUntil;
    }
    laneCount = reserved.length;
    height = math.max(
      320,
      math.max(
            scale.y(this.end),
            reserved.isEmpty ? 0 : reserved.reduce(math.max),
          ) +
          56,
    );
  }

  static const double laneWidth = 155;
  static const double axisWidth = 101;
  static const double labelReservation = 54;
  late final int start;
  late final int end;
  late final int laneCount;
  late final double height;
  late final DesktopTimelineScale scale;
  final List<DesktopTimelineEntry> entries = [];
  double get contentWidth =>
      axisWidth + math.max(1, laneCount) * laneWidth + 18;
}

class DesktopTimelineGraph extends StatefulWidget {
  const DesktopTimelineGraph({
    super.key,
    required this.records,
    required this.allRecords,
    this.start,
    this.end,
    required this.exact,
    required this.zoom,
    required this.onSelected,
    this.selectedId,
  });

  final List<Map<String, dynamic>> records;
  final List<Map<String, dynamic>> allRecords;
  final int? start;
  final int? end;
  final bool exact;
  final double zoom;
  final ValueChanged<Map<String, dynamic>> onSelected;
  final String? selectedId;

  @override
  State<DesktopTimelineGraph> createState() => _DesktopTimelineGraphState();
}

class _DesktopTimelineGraphState extends State<DesktopTimelineGraph> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  @override
  void didUpdateWidget(DesktopTimelineGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.start != widget.start ||
        oldWidget.end != widget.end ||
        oldWidget.exact != widget.exact ||
        oldWidget.zoom != widget.zoom ||
        oldWidget.records.map((r) => r['id']).join('|') !=
            widget.records.map((r) => r['id']).join('|')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_vertical.hasClients) _vertical.jumpTo(0);
        if (_horizontal.hasClients) _horizontal.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final labelSpace = math.max(
      54.0,
      textScaler.scale(13) * 1.35 + textScaler.scale(10) * 1.2 + 22,
    );
    final layout = DesktopTimelineLayout(
      records: widget.records,
      allRecords: widget.allRecords,
      start: widget.start,
      end: widget.end,
      exact: widget.exact,
      zoom: widget.zoom,
      labelSpace: labelSpace,
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        border: Border.all(color: _separator),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.chart_bar_alt_fill,
                  size: 18,
                  color: Color(0xff526d65),
                ),
                const SizedBox(width: 9),
                const Text(
                  '并行政权',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  '${layout.entries.length} 条记录',
                  style: const TextStyle(fontSize: 12, color: _secondary),
                ),
                const Spacer(),
                Text(
                  widget.exact ? '等比例刻度' : '紧凑刻度',
                  style: const TextStyle(fontSize: 12, color: _secondary),
                ),
              ],
            ),
          ),
          Container(height: .5, color: _separator),
          if (layout.entries.isEmpty)
            const SizedBox(
              height: 280,
              child: Center(
                child: Text(
                  '没有符合条件的历史记录',
                  style: TextStyle(fontSize: 14, color: _secondary),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = math.max(
                  constraints.maxWidth,
                  layout.contentWidth,
                );
                return SizedBox(
                  key: const ValueKey('desktop-timeline-viewport'),
                  height: 620,
                  child: CupertinoScrollbar(
                    controller: _vertical,
                    thumbVisibility: true,
                    notificationPredicate: (notification) =>
                        notification.metrics.axis == Axis.vertical,
                    child: CupertinoScrollbar(
                      controller: _horizontal,
                      thumbVisibility: true,
                      scrollbarOrientation: ScrollbarOrientation.bottom,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        key: const ValueKey('desktop-timeline-vertical-scroll'),
                        controller: _vertical,
                        primary: false,
                        child: SingleChildScrollView(
                          key: const ValueKey(
                            'desktop-timeline-horizontal-scroll',
                          ),
                          controller: _horizontal,
                          primary: false,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: width,
                            height: math.max(620, layout.height),
                            child: FocusTraversalGroup(
                              policy: OrderedTraversalPolicy(),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ExcludeSemantics(
                                      child: CustomPaint(
                                        painter: _TimelinePainter(
                                          layout: layout,
                                          selectedId: widget.selectedId,
                                          textStyle: CupertinoTheme.of(context)
                                              .textTheme
                                              .textStyle,
                                        ),
                                      ),
                                    ),
                                  ),
                                  for (
                                    var i = 0;
                                    i < layout.entries.length;
                                    i++
                                  )
                                    Positioned(
                                      left: layout.entries[i].x + 9,
                                      top: layout.entries[i].startY - 14,
                                      width:
                                          DesktopTimelineLayout.laneWidth - 21,
                                      height: labelSpace - 5,
                                      child: FocusTraversalOrder(
                                        order: NumericFocusOrder(i.toDouble()),
                                        child: _TimelineLabel(
                                          key: ValueKey(
                                            'desktop-record-${layout.entries[i].record['id']}',
                                          ),
                                          entry: layout.entries[i],
                                          selected:
                                              widget.selectedId ==
                                              layout.entries[i].record['id'],
                                          onSelected: widget.onSelected,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          Container(height: .5, color: _separator),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  CupertinoIcons.info_circle,
                  size: 14,
                  color: _secondary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${widget.exact ? '同一高度代表同一年，所有时间段严格等比例。' : '同年对齐；无起讫事件的长区间会统一折叠，并标明省略年数。'} '
                    '圆点为真实起讫，边界箭头表示延续。${layout.contentWidth > 650 ? '可横向滚动查看并立支流。' : ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.65,
                      color: _secondary,
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
}

class _TimelineLabel extends StatefulWidget {
  const _TimelineLabel({
    super.key,
    required this.entry,
    required this.selected,
    required this.onSelected,
  });
  final DesktopTimelineEntry entry;
  final bool selected;
  final ValueChanged<Map<String, dynamic>> onSelected;
  @override
  State<_TimelineLabel> createState() => _TimelineLabelState();
}

class _TimelineLabelState extends State<_TimelineLabel> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final textStyle = CupertinoTheme.of(context).textTheme.textStyle;
    final highlighted = widget.selected || _focused;
    final background = highlighted
        ? entry.color.withValues(alpha: .11)
        : _hovered
        ? const Color(0xfff5f5f7)
        : CupertinoColors.white;
    return Semantics(
      label:
          '${entry.record['name']}，${dateRange(entry.record)}。'
          '${entry.continuesBefore ? '开始早于所选时代。' : ''}'
          '${entry.continuesAfter ? '结束晚于所选时代。' : ''}查看详情',
      selected: widget.selected,
      button: true,
      excludeSemantics: true,
      onTap: () => widget.onSelected(entry.record),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: highlighted
                  ? entry.color.withValues(alpha: .32)
                  : background,
            ),
          ),
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            minimumSize: Size.zero,
            alignment: Alignment.centerLeft,
            onFocusChange: (value) => setState(() => _focused = value),
            onPressed: () => widget.onSelected(entry.record),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${entry.record['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle.copyWith(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: highlighted ? entry.color : _ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  dateRange(entry.record),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle.copyWith(
                    fontSize: 10,
                    height: 1.2,
                    color: _secondary,
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

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.layout,
    required this.selectedId,
    required this.textStyle,
  });
  final DesktopTimelineLayout layout;
  final String? selectedId;
  final TextStyle textStyle;

  void _text(
    Canvas canvas,
    String value,
    Offset offset, {
    double size = 10,
    Color color = _secondary,
    bool right = false,
    FontWeight weight = FontWeight.w400,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: textStyle.copyWith(
          fontSize: size,
          color: color,
          fontWeight: weight,
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      offset - Offset(right ? painter.width : 0, painter.height / 2),
    );
  }

  void _arrow(Canvas canvas, Offset at, Color color, {required bool upward}) {
    final dy = upward ? 5.0 : -5.0;
    canvas.drawPath(
      Path()
        ..moveTo(at.dx - 4, at.dy + dy)
        ..lineTo(at.dx, at.dy)
        ..lineTo(at.dx + 4, at.dy + dy),
      Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = _separator
      ..strokeWidth = .65;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 77, size.height),
      Paint()..color = const Color(0xfffafafb),
    );
    _text(
      canvas,
      '年份',
      const Offset(20, 25),
      size: 11,
      weight: FontWeight.w500,
    );
    for (var lane = 0; lane < layout.laneCount; lane++) {
      final x =
          DesktopTimelineLayout.axisWidth +
          lane * DesktopTimelineLayout.laneWidth;
      _text(
        canvas,
        '支流 ${(lane + 1).toString().padLeft(2, '0')}',
        Offset(x + 14, 25),
        size: 10,
        color: const Color(0xff9b9da4),
      );
    }
    for (final year in layout.scale.ticks) {
      final y = layout.scale.y(year);
      canvas.drawLine(Offset(78, y), Offset(size.width - 15, y), grid);
      _text(
        canvas,
        year == 1 ? '公元 1' : yearText(year),
        Offset(65, y),
        right: true,
      );
    }
    for (final entry in layout.entries) {
      final selected = selectedId == entry.record['id'];
      final x = entry.x;
      final rail = Paint()
        ..color = entry.color.withValues(alpha: selected ? 1 : .78)
        ..strokeWidth = selected ? 3 : 2.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(x, entry.startY),
        Offset(x, entry.endY),
        Paint()
          ..color = entry.color.withValues(alpha: .06)
          ..strokeWidth = selected ? 12 : 8
          ..strokeCap = StrokeCap.round,
      );
      if (entry.record['approximate'] == true) {
        for (var y = entry.startY; y < entry.endY; y += 8) {
          canvas.drawLine(
            Offset(x, y),
            Offset(x, math.min(y + 4.5, entry.endY)),
            rail,
          );
        }
      } else {
        canvas.drawLine(Offset(x, entry.startY), Offset(x, entry.endY), rail);
      }
      if (entry.continuesAfter) {
        _arrow(canvas, Offset(x, entry.endY), entry.color, upward: false);
      } else {
        canvas.drawCircle(
          Offset(x, entry.endY),
          2.7,
          Paint()..color = CupertinoColors.white,
        );
        canvas.drawCircle(
          Offset(x, entry.endY),
          2.7,
          Paint()
            ..color = entry.color
            ..strokeWidth = 1.5
            ..style = PaintingStyle.stroke,
        );
      }
      if (entry.continuesBefore) {
        _arrow(canvas, Offset(x, entry.startY), entry.color, upward: true);
      } else {
        canvas.drawCircle(
          Offset(x, entry.startY),
          4.4,
          Paint()..color = CupertinoColors.white,
        );
        canvas.drawCircle(
          Offset(x, entry.startY),
          4.4,
          Paint()
            ..color = entry.color
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      }
    }
    for (final fold in layout.scale.folds) {
      final top = layout.scale.y(fold.start);
      final bottom = layout.scale.y(fold.end);
      final mid = (top + bottom) / 2;
      canvas.drawRect(
        Rect.fromLTRB(78, top, size.width, bottom),
        Paint()..color = const Color(0xfff7f7fa),
      );
      final foldPaint = Paint()
        ..color = const Color(0xffd2d3d9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8;
      final path = Path();
      for (var x = 84.0; x < size.width - 12; x += 22) {
        path.moveTo(x, mid);
        path.relativeQuadraticBezierTo(5, -5, 10, 0);
        path.relativeQuadraticBezierTo(5, 5, 10, 0);
      }
      canvas.drawPath(path, foldPaint);
      final label =
          '${yearText(fold.start)}—${yearText(fold.end)} · 折叠 ${yearSpan(fold.start, fold.end)} 年';
      final labelPaint = TextPainter(
        text: TextSpan(
          text: label,
          style: textStyle.copyWith(fontSize: 10, color: _secondary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Place the explanation near the year axis, visible before horizontal scrolling.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(111, mid - 12, labelPaint.width + 20, 24),
          const Radius.circular(12),
        ),
        Paint()..color = const Color(0xfff7f7fa),
      );
      labelPaint.paint(canvas, Offset(121, mid - labelPaint.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.selectedId != selectedId ||
      oldDelegate.textStyle != textStyle;
}
