import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'history.dart';

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
  final _search = TextEditingController();
  final _scroll = ScrollController();
  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _change(VoidCallback action) {
    setState(action);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final records = data.filter(era: _era, query: _query);
    final era = data.eras.where((e) => e['id'] == _era).firstOrNull;
    final selectedEra = _query.isEmpty ? era : null;
    final title = _query.isNotEmpty
        ? '搜索结果'
        : era?['name'] as String? ?? (_era == 'all' ? '全部历史记录' : '一览华夏，纵贯古今');
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        key: const PageStorageKey('timeline-scroll'),
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 500 ? 16 : 28,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'HISTORY, IN PERSPECTIVE',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 2.6,
                    color: Color(0xff8b7664),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xff284c42),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  era?['description'] as String? ?? '王朝更迭之外，看见同一时代的不同支流。',
                  style: const TextStyle(color: Color(0xff6e756b), height: 1.7),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _search,
                  onChanged: (value) => _change(() => _query = value),
                  decoration: InputDecoration(
                    hintText: '搜索朝代、政权、地域或注释',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            tooltip: '清除搜索',
                            onPressed: () {
                              _search.clear();
                              _change(() => _query = '');
                            },
                            icon: const Icon(Icons.close),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final e in [
                        {'id': 'overview', 'name': '全局主线'},
                        {'id': 'all', 'name': '全部记录'},
                        ...data.eras,
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('${e['name']}'),
                            selected: _era == e['id'] && _query.isEmpty,
                            onSelected: (_) {
                              _search.clear();
                              _change(() {
                                _era = e['id'] as String;
                                _query = '';
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.account_tree_outlined, size: 18),
                          label: Text('脉络图'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.view_list_outlined, size: 18),
                          label: Text('年代表'),
                        ),
                      ],
                      selected: {_list},
                      onSelectionChanged: (v) =>
                          setState(() => _list = v.first),
                    ),
                    if (!_list)
                      FilterChip(
                        label: const Text('严格等比例'),
                        selected: _exact,
                        onSelected: (value) => _change(() => _exact = value),
                      ),
                    if (!_list)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '缩小时间刻度',
                            onPressed: _zoom > .6
                                ? () => setState(
                                    () => _zoom = (_zoom - .2).clamp(.6, 2.2),
                                  )
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '${(_zoom * 100).round()}%',
                            style: const TextStyle(fontSize: 12),
                          ),
                          IconButton(
                            tooltip: '放大时间刻度',
                            onPressed: _zoom < 2.2
                                ? () => setState(
                                    () => _zoom = (_zoom + .2).clamp(.6, 2.2),
                                  )
                                : null,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    Text(
                      '${records.length} 条记录',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Center(child: Text('没有找到对应记录，试试其他名称或地域。')),
                  )
                else if (_list)
                  ...records.map(
                    (d) => Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 9,
                        ),
                        title: Text(
                          '${d['name']}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('${dateRange(d)}\n${d['region']}'),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => showDynasty(context, data, d),
                      ),
                    ),
                  )
                else ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xffeaf0e6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _exact
                          ? '等比例刻度：同年对齐。名称以引线连接到准确起点，标签位置不代表年份。'
                          : '紧凑刻度：所有分支适配一屏宽，同年对齐；各段比例不同。完整起讫年见名称下方。',
                      style: const TextStyle(
                        color: Color(0xff3c5c4c),
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ),
                  if (selectedEra != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        '边界箭头表示超出所选时代，不是真实起讫；标签仍显示完整年代。',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final layout = TimelineLayout(
                        records: records,
                        start: selectedEra?['start'] as int?,
                        end: selectedEra?['end'] as int?,
                        exact: _exact,
                        zoom: _zoom,
                        width: constraints.maxWidth,
                        textScale: MediaQuery.textScalerOf(context).scale(1),
                      );
                      return TimelineGraph(
                        layout: layout,
                        allRecords: data.dynasties,
                        onSelected: (d) => showDynasty(context, data, d),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  '朝代、时代分期与现代政体不同。轨道不代表疆域或正统地位；这是一份学习年表，不是穷尽名录。',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xff7b7c70),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
    labelHeight = 56 * textScale.clamp(1, 3);
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
            height: layout.labelHeight - 5,
            child: Semantics(
              button: true,
              label: '${item.record['name']}，${dateRange(item.record)}，查看详情',
              excludeSemantics: true,
              onTap: () => onSelected(item.record),
              child: Material(
                color: const Color(0xfffffdf8),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelected(item.record),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 29,
                          decoration: BoxDecoration(
                            color: color(item.record),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${item.record['name']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dateRange(item.record),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xff7d7d70),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
    Color color = const Color(0xff7d7d70),
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
            ..color = const Color(0xffe4e5d9)
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
      canvas.drawCircle(
        Offset(x, a),
        3.1,
        Paint()..color = const Color(0xfffffdf7),
      );
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
  Map<String, dynamic> d,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .72,
      minChildSize: .35,
      maxChildSize: .95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${d['name']}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭详情',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            '${d['english']}',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 14),
          Text(dateRange(d), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('${data.groupName(d['group'] as String)} · ${d['region']}'),
          const SizedBox(height: 22),
          const Text('纪年说明', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SelectableText('${d['note']}', style: const TextStyle(height: 1.8)),
          const SizedBox(height: 22),
          const Text('参考来源', style: TextStyle(fontWeight: FontWeight.w700)),
          ...data.sources
              .where((s) => (d['sourceIds'] as List).contains(s['id']))
              .map((s) => SourceTile(source: s)),
          const SizedBox(height: 18),
          const Text(
            '同期政权 · 存续年份有交集',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: data
                .contemporaries(d)
                .map(
                  (r) => ActionChip(
                    label: Text('${r['name']}'),
                    onPressed: () {
                      Navigator.pop(context);
                      showDynasty(context, data, r);
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          const Text(
            '起讫年相接不表示全年同时统治；具体建立、迁都、失去领土和终结口径见各条注释。',
            style: TextStyle(fontSize: 11, height: 1.6),
          ),
        ],
      ),
    ),
  );
}

class SourceTile extends StatelessWidget {
  const SourceTile({super.key, required this.source});
  final Map<String, dynamic> source;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text('${source['title']}', style: const TextStyle(fontSize: 13)),
    subtitle: SelectableText(
      '${source['url']}',
      style: const TextStyle(fontSize: 10),
    ),
    trailing: IconButton(
      tooltip: '打开参考来源',
      icon: const Icon(Icons.open_in_new, size: 19),
      onPressed: () async {
        final ok = await launchUrl(
          Uri.parse(source['url'] as String),
          mode: LaunchMode.externalApplication,
        );
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('无法打开链接，请复制网址到浏览器。')));
        }
      },
    ),
  );
}
