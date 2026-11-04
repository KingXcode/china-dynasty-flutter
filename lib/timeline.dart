import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import 'history.dart';
import 'app_style.dart';
import 'desktop_timeline.dart';

const timelineColors = [
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

class AppGroupedSection extends StatelessWidget {
  const AppGroupedSection({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppColors.line, width: .8),
      boxShadow: const [
        BoxShadow(
          color: Color(0x04172d25),
          blurRadius: 18,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: child,
  );
}

class AppSectionHeading extends StatelessWidget {
  const AppSectionHeading(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.secondary,
      ),
    ),
  );
}

class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key, required this.data});
  final HistoryData data;
  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  String _era = 'overview', _query = '';
  bool _exact = false, _list = false;
  double _zoom = 1;
  Map<String, dynamic>? _selected;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _change(VoidCallback action) {
    setState(() {
      action();
      _selected = null;
    });
  }

  Future<void> _pickEra() async {
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('浏览时代'),
        message: const Text('时代视图同时显示与该时期重叠的政权'),
        actions: [
          for (final era in [
            {'id': 'overview', 'name': '全局主线'},
            {'id': 'all', 'name': '全部记录'},
            ...widget.data.eras,
          ])
            CupertinoActionSheetAction(
              isDefaultAction: era['id'] == _era,
              onPressed: () => Navigator.pop(context, era['id']),
              child: Text('${era['name']}'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
    if (selected != null && mounted) {
      _search.clear();
      _change(() {
        _era = selected;
        _query = '';
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  Future<void> _displayOptions() async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) => CupertinoPopupSurface(
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '显示设置',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.all(8),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Expanded(child: Text('严格等比例刻度')),
                      CupertinoSwitch(
                        value: _exact,
                        onChanged: (value) {
                          setState(() => _exact = value);
                          refresh(() {});
                        },
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      '关闭时压缩没有起讫节点的长时段；无论哪种模式，同一年始终对齐。',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.secondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      const Expanded(child: Text('时间轴缩放')),
                      CupertinoButton(
                        onPressed: _zoom > .6
                            ? () {
                                setState(
                                  () => _zoom = (_zoom - .2).clamp(.6, 2.2),
                                );
                                refresh(() {});
                              }
                            : null,
                        child: const Icon(CupertinoIcons.minus_circle),
                      ),
                      Text(
                        '${(_zoom * 100).round()}%',
                        style: const TextStyle(fontSize: 14),
                      ),
                      CupertinoButton(
                        onPressed: _zoom < 2.2
                            ? () {
                                setState(
                                  () => _zoom = (_zoom + .2).clamp(.6, 2.2),
                                );
                                refresh(() {});
                              }
                            : null,
                        child: const Icon(CupertinoIcons.plus_circle),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _open(Map<String, dynamic> record, bool desktop) {
    if (desktop) {
      setState(() => _selected = record);
    } else {
      showDynasty(context, widget.data, record);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data, records = data.filter(era: _era, query: _query);
    final era = data.eras.where((e) => e['id'] == _era).firstOrNull;
    final selectedEra = _query.isEmpty ? era : null;
    final label = _query.isNotEmpty
        ? '搜索结果'
        : era?['name'] as String? ?? (_era == 'all' ? '全部记录' : '全局主线');
    final desktop = MediaQuery.sizeOf(context).width >= 1000;
    final segmented = CupertinoSlidingSegmentedControl<bool>(
      groupValue: _list,
      backgroundColor: AppColors.accentSoft,
      thumbColor: AppColors.surface,
      onValueChanged: (value) {
        if (value != null) setState(() => _list = value);
      },
      children: const {
        false: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text('脉络图', style: TextStyle(fontSize: 14)),
        ),
        true: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text('年代表', style: TextStyle(fontSize: 14)),
        ),
      },
    );
    final search = CupertinoSearchTextField(
      controller: _search,
      placeholder: '搜索朝代、政权或地区',
      backgroundColor: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemColor: AppColors.secondary,
      style: const TextStyle(fontFamily: 'NotoSansSC', fontSize: 15),
      onChanged: (v) => _change(() => _query = v),
      onSuffixTap: () {
        _search.clear();
        _change(() => _query = '');
      },
    );
    return CupertinoScrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        key: const PageStorageKey('timeline-scroll'),
        padding: EdgeInsets.fromLTRB(
          desktop ? 28 : 16,
          desktop ? 24 : 16,
          desktop ? 28 : 16,
          24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppPageIntro(
                  index: '01 / 时间探索',
                  title: '历史脉络',
                  subtitle: '沿着时间线，发现历史的不同支流。',
                  trailing: desktop
                      ? Text(
                          '${data.dynasties.length} 项记录 · 4,000 余年',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.secondary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 18),
                if (desktop)
                  Row(
                    children: [
                      SizedBox(width: 230, child: segmented),
                      const Spacer(),
                      SizedBox(width: 330, child: search),
                    ],
                  )
                else ...[
                  search,
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: segmented),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          minimumSize: const Size(44, 44),
                          onPressed: _pickEra,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(CupertinoIcons.chevron_down, size: 13),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Text(
                      '${records.length} 项',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CupertinoButton(
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(44, 44),
                      onPressed: _displayOptions,
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                      child: const Icon(
                        CupertinoIcons.slider_horizontal_3,
                        size: 20,
                        semanticLabel: '显示设置',
                      ),
                    ),
                  ],
                ),
                if (records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Center(
                      child: Text(
                        '没有找到对应记录\n试试其他名称或地域',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.secondary,
                          height: 1.8,
                        ),
                      ),
                    ),
                  )
                else if (_list)
                  AppGroupedSection(
                    child: Column(
                      children: [
                        for (final record in records)
                          CupertinoListTile(
                            title: Text(
                              '${record['name']}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            subtitle: Text(
                              '${dateRange(record)} · ${record['region']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 13,
                            ),
                            trailing: const CupertinoListTileChevron(),
                            onTap: () => showDynasty(context, data, record),
                          ),
                      ],
                    ),
                  )
                else if (desktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppGroupedSection(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ChartCaption(
                                exact: _exact,
                                era: selectedEra != null,
                              ),
                              DesktopTimelineGraph(
                                records: records,
                                allRecords: data.dynasties,
                                start: selectedEra?['start'] as int?,
                                end: selectedEra?['end'] as int?,
                                exact: _exact,
                                zoom: _zoom,
                                selectedId: _selected?['id'] as String?,
                                onSelected: (d) => _open(d, true),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      SizedBox(
                        width: 286,
                        child: AppGroupedSection(
                          child: _selected == null
                              ? const Padding(
                                  padding: EdgeInsets.all(22),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '从这里开始探索',
                                        style: TextStyle(
                                          fontSize: 10,
                                          letterSpacing: 1.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.accent,
                                        ),
                                      ),
                                      SizedBox(height: 24),
                                      ExcludeSemantics(
                                        child: AppOrbitMark(size: 62),
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        '选一个朝代，出发',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(height: 10),
                                      Text(
                                        '点选时间轴上的名字，了解它的年代、地域，以及同时存在的政权。',
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.7,
                                          color: AppColors.secondary,
                                        ),
                                      ),
                                      SizedBox(height: 20),
                                      Text(
                                        '并行的轨道代表同时存在的政权，不代表地理位置或正统地位。',
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.7,
                                          color: AppColors.subtle,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : SizedBox(
                                  height: 696,
                                  child: SingleChildScrollView(
                                    child: DynastyDetailsBody(
                                      data: data,
                                      record: _selected!,
                                      onRelated: (r) =>
                                          setState(() => _selected = r),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  )
                else
                  AppGroupedSection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ChartCaption(exact: _exact, era: selectedEra != null),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final layout = TimelineLayout(
                                records: records,
                                start: selectedEra?['start'] as int?,
                                end: selectedEra?['end'] as int?,
                                exact: _exact,
                                zoom: _zoom,
                                width: constraints.maxWidth,
                                textScale: MediaQuery.textScalerOf(context)
                                    .scale(1),
                              );
                              return TimelineGraph(
                                layout: layout,
                                allRecords: data.dynasties,
                                onSelected: (d) => _open(d, false),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '紧凑模式各段比例不同，同年仍对齐。史前文化与传说另列于阅读说明。年代、范围与异说详见每项记录。',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.secondary,
                      height: 1.7,
                    ),
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

class _ChartCaption extends StatelessWidget {
  const _ChartCaption({required this.exact, required this.era});
  final bool exact, era;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: const BoxDecoration(
      color: AppColors.surface,
      border: Border(bottom: BorderSide(color: AppColors.line, width: .8)),
    ),
    child: Text(
      '${exact ? '等比例刻度' : '紧凑刻度'} · 同年对齐 · 点按查看${era ? ' · 边界箭头表示超出本时代' : ''}',
      style: const TextStyle(
        fontSize: 11,
        color: AppColors.secondary,
        height: 1.5,
      ),
    ),
  );
}

/// Every track shares this mapping; no bar is lengthened to fit its label.
class TimelineLayout {
  TimelineLayout({
    required this.records,
    int? start,
    int? end,
    required this.exact,
    required this.zoom,
    required this.width,
    double textScale = 1,
  }) {
    this.start =
        start ?? records.map((d) => d['start'] as int).reduce(math.min);
    this.end = end ?? records.map((d) => d['end'] as int).reduce(math.max);
    labelHeight = 52 * textScale.clamp(1, 3);
    final starts = <int, int>{};
    final nodes = <int>{this.start, this.end};
    for (final d in records) {
      final a = math.max(this.start, d['start'] as int),
          b = math.min(this.end, d['end'] as int);
      nodes.addAll([a, b]);
      starts[a] = (starts[a] ?? 0) + 1;
    }
    events = nodes.toList()..sort();
    double cursor = 50;
    for (var i = 0; i < events.length; i++) {
      final year = events[i];
      positions[year] = exact
          ? 50 + yearSpan(this.start, year) * 1.2 * zoom
          : cursor;
      if (i + 1 < events.length) {
        final gap = yearSpan(year, events[i + 1]);
        cursor +=
            math.max(28, (starts[year] ?? 0) * labelHeight + 10) +
            math.min(48, math.max(12, math.log(gap + 1) / math.ln2 * 5)) * zoom;
      }
    }
    final lanes = <int>[];
    double lastLabel = -labelHeight;
    for (final d in records) {
      final a = math.max(this.start, d['start'] as int),
          b = math.min(this.end, d['end'] as int);
      var lane = lanes.indexWhere((last) => last <= a);
      if (lane < 0) {
        lane = lanes.length;
        lanes.add(b);
      } else {
        lanes[lane] = b;
      }
      final labelY = math.max(y(a) - 18, lastLabel + labelHeight);
      items.add(TimelineItem(d, a, b, lane, labelY));
      lastLabel = labelY;
    }
    laneCount = lanes.length;
    laneStep = math.min(
      width >= 700 ? 18.0 : 10.0,
      (width * .38 - 48).clamp(20, 180) / math.max(1, laneCount),
    );
    labelX = 52 + laneCount * laneStep + 15;
    height = math.max(y(this.end) + 70, lastLabel + labelHeight + 24);
  }
  final List<Map<String, dynamic>> records;
  final bool exact;
  final double zoom, width;
  late final int start, end, laneCount;
  late final List<int> events;
  final positions = <int, double>{};
  final items = <TimelineItem>[];
  late final double labelHeight, laneStep, labelX, height;
  double y(int year) => positions[year]!;
}

class TimelineItem {
  TimelineItem(this.record, this.start, this.end, this.lane, this.labelY);
  final Map<String, dynamic> record;
  final int start, end, lane;
  final double labelY;
}

class TimelineGraph extends StatelessWidget {
  const TimelineGraph({
    super.key,
    required this.layout,
    required this.allRecords,
    required this.onSelected,
  });
  final TimelineLayout layout;
  final List<Map<String, dynamic>> allRecords;
  final ValueChanged<Map<String, dynamic>> onSelected;
  Color color(Map<String, dynamic> d) =>
      timelineColors[allRecords.indexWhere((r) => r['id'] == d['id']).abs() %
          timelineColors.length];
  @override
  Widget build(BuildContext context) => SizedBox(
    height: layout.height,
    width: layout.width,
    child: Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: TimelinePainter(layout, color)),
          ),
        ),
        for (final item in layout.items)
          Positioned(
            left: layout.labelX,
            right: 0,
            top: item.labelY,
            height: layout.labelHeight - 4,
            child: Semantics(
              button: true,
              label: '${item.record['name']}，${dateRange(item.record)}，查看详情',
              excludeSemantics: true,
              onTap: () => onSelected(item.record),
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                minimumSize: Size.zero,
                borderRadius: BorderRadius.circular(7),
                color: AppColors.surface,
                onPressed: () => onSelected(item.record),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 27,
                      decoration: BoxDecoration(
                        color: color(item.record),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.record['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateRange(item.record),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      CupertinoIcons.chevron_right,
                      size: 11,
                      color: AppColors.subtle,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class TimelinePainter extends CustomPainter {
  TimelinePainter(this.layout, this.color);
  final TimelineLayout layout;
  final Color Function(Map<String, dynamic>) color;
  void label(
    Canvas canvas,
    String text,
    Offset offset, {
    double size = 10,
    Color color = AppColors.secondary,
    double width = 120,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'NotoSansSC',
          fontSize: size,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: width);
    p.paint(canvas, offset);
  }

  @override
  void paint(Canvas canvas, Size size) {
    label(canvas, '年份', const Offset(7, 10));
    label(
      canvas,
      '朝代 / 政权 · 点按查看',
      Offset(layout.labelX, 10),
      width: size.width - layout.labelX,
    );
    double last = -100;
    for (var i = 0; i < layout.events.length; i++) {
      final year = layout.events[i], y = layout.y(year);
      if (y - last > 23) {
        canvas.drawLine(
          Offset(44, y),
          Offset(size.width, y),
          Paint()
            ..color = AppColors.line
            ..strokeWidth = .7,
        );
        label(canvas, yearText(year), Offset(0, y - 6), width: 44, size: 9);
        last = y;
      }
      if (!layout.exact &&
          i + 1 < layout.events.length &&
          yearSpan(year, layout.events[i + 1]) > 80) {
        final next = layout.y(layout.events[i + 1]);
        label(
          canvas,
          '⋯ ${yearSpan(year, layout.events[i + 1])} 年间隔 · 已压缩',
          Offset(layout.labelX + 8, next - 36),
          width: size.width - layout.labelX - 8,
          size: 9,
        );
      }
    }
    for (final item in layout.items) {
      final x = 52 + item.lane * layout.laneStep,
          a = layout.y(item.start),
          b = layout.y(item.end),
          c = color(item.record);
      final paint = Paint()
        ..color = c
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke;
      if (item.record['approximate'] == true) {
        for (double y = a; y < b; y += 8) {
          canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 5, b)), paint);
        }
      } else {
        canvas.drawLine(Offset(x, a), Offset(x, b), paint);
      }
      canvas.drawCircle(Offset(x, a), 3.1, Paint()..color = AppColors.surface);
      canvas.drawCircle(Offset(x, a), 3.1, paint..strokeWidth = 1.4);
      canvas.drawCircle(Offset(x, b), 2.3, Paint()..color = c);
      final connector = Path()
        ..moveTo(x + 4, a)
        ..lineTo(layout.labelX - 8, a)
        ..lineTo(layout.labelX, item.labelY + 18);
      canvas.drawPath(
        connector,
        Paint()
          ..color = c.withValues(alpha: .45)
          ..strokeWidth = .8
          ..style = PaintingStyle.stroke,
      );
      if ((item.record['start'] as int) < layout.start) {
        canvas.drawPath(
          Path()
            ..moveTo(x - 4, a + 7)
            ..lineTo(x, a)
            ..lineTo(x + 4, a + 7),
          paint,
        );
      }
      if ((item.record['end'] as int) > layout.end) {
        canvas.drawPath(
          Path()
            ..moveTo(x - 4, b - 7)
            ..lineTo(x, b)
            ..lineTo(x + 4, b - 7),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant TimelinePainter oldDelegate) =>
      oldDelegate.layout != layout;
}

void showDynasty(
  BuildContext context,
  HistoryData data,
  Map<String, dynamic> record,
) {
  Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (context) => CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text('${record['name']}'),
          previousPageTitle: '历史脉络',
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: DynastyDetailsBody(
              data: data,
              record: record,
              onRelated: (related) => showDynasty(context, data, related),
            ),
          ),
        ),
      ),
    ),
  );
}

class DynastyDetailsBody extends StatelessWidget {
  const DynastyDetailsBody({
    super.key,
    required this.data,
    required this.record,
    required this.onRelated,
  });
  final HistoryData data;
  final Map<String, dynamic> record;
  final ValueChanged<Map<String, dynamic>> onRelated;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '历史档案',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.6,
            color: AppColors.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${record['name']}',
          style: const TextStyle(
            fontSize: 25,
            height: 1.35,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${record['english']}',
          style: const TextStyle(fontSize: 12, color: AppColors.secondary),
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.accentSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            dateRange(record),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${data.groupName(record['group'] as String)} · ${record['region']}',
          style: const TextStyle(
            fontSize: 12,
            height: 1.6,
            color: AppColors.secondary,
          ),
        ),
        if ((record['note'] as String? ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 24),
          const AppSectionHeading('纪年说明'),
          AppSelectableText(
            '${record['note']}',
            style: const TextStyle(
              fontSize: 14,
              height: 1.8,
              color: AppColors.ink,
            ),
          ),
        ],
        if ((record['sourceIds'] as List).isNotEmpty) ...[
          const SizedBox(height: 24),
          const AppSectionHeading('参考来源'),
          ...data.sources
              .where((s) => (record['sourceIds'] as List).contains(s['id']))
              .map((s) => SourceTile(source: s, compact: true)),
        ],
        const SizedBox(height: 22),
        const AppSectionHeading('同期政权'),
        const Text(
          '存续年份有交集，不表示始终同时统治。',
          style: TextStyle(fontSize: 11, color: AppColors.secondary),
        ),
        const SizedBox(height: 8),
        ...data
            .contemporaries(record)
            .map(
              (r) => CupertinoListTile(
                padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                title: Text(
                  '${r['name']}',
                  style: const TextStyle(fontSize: 14, color: AppColors.accent),
                ),
                trailing: const CupertinoListTileChevron(),
                onTap: () => onRelated(r),
              ),
            ),
      ],
    ),
  );
}

class SourceTile extends StatelessWidget {
  const SourceTile({super.key, required this.source, this.compact = false});
  final Map<String, dynamic> source;
  final bool compact;
  Future<void> _open(BuildContext context) async {
    bool opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(source['url'] as String),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('无法打开链接'),
          content: AppSelectableText('${source['url']}'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 16),
    child: CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 13),
      onPressed: () => _open(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${source['title']}',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  Uri.tryParse('${source['url']}')?.host ?? '参考来源',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Icon(CupertinoIcons.arrow_up_right, size: 13),
          ),
        ],
      ),
    ),
  );
}

/// Read-only selectable prose using iOS selection handles and menu.
class AppSelectableText extends StatefulWidget {
  const AppSelectableText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;
  @override
  State<AppSelectableText> createState() => _AppSelectableTextState();
}

class _AppSelectableTextState extends State<AppSelectableText> {
  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectableRegion(
    focusNode: _focus,
    selectionControls: cupertinoTextSelectionControls,
    child: Text(widget.text, style: widget.style),
  );
}
