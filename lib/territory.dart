// Bundled Cliopatria source intervals, never an interpolated yearly reconstruction.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const territoryMinimumYear = -221;
const territoryMaximumYear = 1911;
const territorySourceUrl =
    'https://github.com/Seshat-Global-History-Databank/cliopatria/tree/5f433377139a6eeaeacbdc894b70f8805b72c8b5';
int territorySliderYear(int value) => value < 0 ? value : value + 1;
int territoryYearSlider(int year) => year < 0 ? year : year - 1;
// Dart ~/ truncates toward zero; BCE shards require floor.
int territoryCentury(int year) => (year / 100).floor() * 100;
bool territoryValidYear(int year) =>
    year != 0 && year >= territoryMinimumYear && year <= territoryMaximumYear;
String territoryYearText(int year) =>
    year < 0 ? '公元前 ${-year} 年' : '公元 $year 年';
String _shortYear(int year) => year < 0 ? '前${-year}' : '$year';
String _period(int from, int to) => '${_shortYear(from)}—${_shortYear(to)} 年';
bool _inRange(int year, List<dynamic> range) =>
    (range[0] as num) <= year && year <= (range[1] as num);
Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<dynamic> _list(dynamic value) => value is List ? value : <dynamic>[];

/// Original Mercator projection; GeoJSON is [longitude, latitude], EPSG:4326.
Offset territoryProject(List<dynamic> coordinate) {
  final lon = (coordinate[0] as num).toDouble();
  final lat = (coordinate[1] as num).toDouble().clamp(-80.0, 80.0);
  final merc =
      math.log(math.tan(math.pi / 4 + lat * math.pi / 360)) * 180 / math.pi;
  return Offset((lon - 68) * 13.15, (71.16 - merc) * 13.15);
}

class TerritoryGeometry {
  TerritoryGeometry._(this.path, this.bounds, this.labelPoint, this.labelArea);
  final Path path;
  final Rect bounds;
  final Offset? labelPoint;
  final double labelArea;
  factory TerritoryGeometry.fromJson(Map<String, dynamic> geometry) {
    final type = geometry['type'];
    if (type != 'Polygon' && type != 'MultiPolygon') {
      throw FormatException('Unsupported geometry: $type');
    }
    final coordinates = _list(geometry['coordinates']);
    final polygons = type == 'Polygon' ? [coordinates] : coordinates;
    final path = Path()..fillType = PathFillType.evenOdd;
    Offset? label;
    double largestArea = -1;
    for (final polygon in polygons) {
      final rings = _list(polygon);
      for (var index = 0; index < rings.length; index++) {
        final ring = _list(rings[index]);
        if (ring.length < 4) continue;
        final points = ring.map((p) => territoryProject(_list(p))).toList();
        path.moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        path.close(); // Holes remain in the same even/odd path.
        if (index != 0) continue;
        double twiceArea = 0, cx = 0, cy = 0;
        for (var i = 0; i < points.length - 1; i++) {
          final a = points[i], b = points[i + 1];
          final cross = a.dx * b.dy - b.dx * a.dy;
          twiceArea += cross;
          cx += (a.dx + b.dx) * cross;
          cy += (a.dy + b.dy) * cross;
        }
        if (twiceArea.abs() > largestArea && twiceArea.abs() > .000001) {
          largestArea = twiceArea.abs();
          label = Offset(cx / (3 * twiceArea), cy / (3 * twiceArea));
        }
      }
    }
    // A concave centroid may lie outside the polygon, or inside a hole.
    if (label != null && !path.contains(label)) label = null;
    return TerritoryGeometry._(path, path.getBounds(), label, largestArea / 2);
  }
}

class TerritoryFeature {
  TerritoryFeature(this.id, this.properties, this.geometry);
  final int id;
  final Map<String, dynamic> properties;
  final TerritoryGeometry geometry;
  String get name => properties['Name'] as String;
  int get from => (properties['FromYear'] as num).toInt();
  int get to => (properties['ToYear'] as num).toInt();
  double get area => (properties['Area'] as num?)?.toDouble() ?? 0;
  bool activeAt(int year) => from <= year && year <= to;
}

bool territoryAcceptedAt(String name, int year, Map<String, dynamic> audit) {
  final ranges = _list(
    _map(_map(audit['identities'])[name])['canonicalRanges'],
  );
  return ranges.isEmpty || ranges.any((range) => _inRange(year, _list(range)));
}

List<int> territoryChanges(List<dynamic> records, Map<String, dynamic> audit) {
  final changes = <int>{territoryMinimumYear, territoryMaximumYear};
  void add(int year) {
    // Immediately after 1 BCE is 1 CE, not a discarded year zero.
    final candidate = year == 0 ? 1 : year;
    if (territoryValidYear(candidate)) changes.add(candidate);
  }

  for (final row in records) {
    final record = _map(row);
    add((record['from'] as num).toInt());
    add((record['to'] as num).toInt() + 1);
    final identity = _map(_map(audit['identities'])[record['name']]);
    for (final range in _list(identity['canonicalRanges'])) {
      add((range[0] as num).toInt());
      add((range[1] as num).toInt() + 1);
    }
  }
  return changes.toList()..sort();
}

class TerritoryYearData {
  TerritoryYearData(this.active, this.excluded);
  final List<TerritoryFeature> active, excluded;
}

/// Lazy century loading, bounded caches, and failed-request eviction for retry.
class TerritoryRepository {
  TerritoryRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;
  final LinkedHashMap<int, Future<Map<String, dynamic>>> _shards =
      LinkedHashMap();
  final LinkedHashMap<int, TerritoryFeature> _features = LinkedHashMap();
  Map<String, dynamic> names = {}, audit = {};
  List<int> changes = [];
  List<TerritoryGeometry> land = [];
  final Map<String, Color> _colors = {};
  Future<Map<String, dynamic>> _read(String file) async => _map(
    jsonDecode(await _bundle.loadString('assets/map-data/$file', cache: false)),
  );
  Future<void> initialize() async {
    final data = await Future.wait([
      _read('polities.json'),
      _read('audit.json'),
      _read('index.json'),
      _read('land.geojson'),
    ]);
    names = data[0];
    audit = data[1];
    changes = territoryChanges(_list(data[2]['records']), audit);
    land = _list(
      data[3]['features'],
    ).map((row) => TerritoryGeometry.fromJson(_map(row['geometry']))).toList();
    final sorted = names.keys.toList()..sort();
    for (var i = 0; i < sorted.length; i++) {
      _colors[sorted[i]] = HSLColor.fromAHSL(
        1,
        (i * 137.508 + 18) % 360,
        .38,
        .52,
      ).toColor();
    }
  }

  String label(String name) {
    if (name == 'Western Jin') return '晋〔来源未分西晋/东晋〕';
    if (name == 'Han Dynasty') return '汉〔来源统称〕';
    return names[name]?.toString() ?? name;
  }

  Color color(String name) => _colors[name] ?? const Color(0xff547b67);
  Future<Map<String, dynamic>> _loadCentury(int century) {
    final cached = _shards.remove(century);
    if (cached != null) {
      _shards[century] = cached;
      return cached;
    }
    late final Future<Map<String, dynamic>> future;
    future = _read('era-$century.geojson').catchError((Object error) {
      if (identical(_shards[century], future)) _shards.remove(century);
      throw error;
    });
    _shards[century] = future;
    while (_shards.length > 4) {
      _shards.remove(_shards.keys.first);
    }
    return future;
  }

  Future<TerritoryYearData> loadYear(int year) async {
    if (!territoryValidYear(year)) throw ArgumentError.value(year, 'year');
    final data = await _loadCentury(territoryCentury(year));
    final active = <TerritoryFeature>[], excluded = <TerritoryFeature>[];
    for (final row in _list(data['features'])) {
      final json = _map(row), properties = _map(row['properties']);
      final from = (properties['FromYear'] as num).toInt(),
          to = (properties['ToYear'] as num).toInt();
      final name = properties['Name'] as String;
      if (from > year || to < year || !names.containsKey(name)) continue;
      final id = (json['id'] as num).toInt();
      final feature =
          _features.remove(id) ??
          TerritoryFeature(
            id,
            properties,
            TerritoryGeometry.fromJson(_map(json['geometry'])),
          );
      _features[id] = feature;
      (territoryAcceptedAt(name, year, audit) ? active : excluded).add(feature);
    }
    while (_features.length > 160) {
      _features.remove(_features.keys.first);
    }
    active.sort((a, b) => b.area.compareTo(a.area));
    return TerritoryYearData(active, excluded);
  }

  List<String> warnings(
    int year,
    List<TerritoryFeature> active,
    List<TerritoryFeature> excluded,
  ) {
    final messages = <String>[];
    for (final raw in _list(audit['warnings'])) {
      final warning = _map(raw);
      if ((warning['fromYear'] as num) <= year &&
          year <= (warning['toYear'] as num)) {
        messages.add(warning['messageZh'] as String);
      }
    }
    if (excluded.isNotEmpty) {
      messages.add(
        '已不绘制 ${excluded.length} 条明显时间错位的原始记录：${excluded.map((f) => label(f.name)).toSet().join('、')}。空缺没有用其他年份的疆域补齐。',
      );
    }
    final missing = <String>{};
    for (final raw in _list(audit['sourceCoverageGaps'])) {
      final gap = _map(raw);
      if (_list(
        gap['missingSourceIntervals'],
      ).any((range) => _inRange(year, _list(range)))) {
        missing.add(gap['labelZh'] as String);
      }
    }
    for (final raw in _list(audit['missingStandaloneIdentities'])) {
      final gap = _map(raw);
      if (_inRange(year, _list(gap['canonicalRange']))) {
        missing.add(gap['labelZh'] as String);
      }
    }
    if (missing.isNotEmpty) {
      messages.add('已知未能单独绘制：${missing.join('、')}。没有颜色不表示这些政权不存在。');
    }
    if (active.any((f) => f.name == 'Western Jin')) {
      messages.add('“晋”在源文件中统一写作 Western Jin，未可靠区分西晋、东晋，不能据此精确复原两晋疆域。');
    }
    if (active.any((f) => f.name == 'Protectorate of the Western Regions')) {
      messages.add('“西域都护府”是原数据名称，其延续年代及隶属关系需要单独考证，不应理解为本年仍由汉朝直接管辖。');
    }
    if (messages.isEmpty) {
      messages.add('本年没有额外的已知年表冲突提示，不等于数据完整或已经历史学核验。地方势力、短期政权与部分边疆记录仍可能缺失。');
    }
    return messages;
  }
}

class TerritoryPage extends StatefulWidget {
  const TerritoryPage({super.key, required this.dynasties, this.repository});
  final List<Map<String, dynamic>> dynasties;
  final TerritoryRepository? repository;
  @override
  State<TerritoryPage> createState() => _TerritoryPageState();
}

class _TerritoryPageState extends State<TerritoryPage>
    with WidgetsBindingObserver {
  late final TerritoryRepository _repository;
  int _year = 1142, _requestVersion = 0;
  bool _ready = false, _loading = true, _error = false, _playing = false;
  List<TerritoryFeature> _active = [], _excluded = [];
  TerritoryFeature? _selected;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    final queryYear = int.tryParse(Uri.base.queryParameters['year'] ?? '');
    if (queryYear != null && territoryValidYear(queryYear)) _year = queryYear;
    _repository = widget.repository ?? TerritoryRepository();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) {
      _timer?.cancel();
      _timer = null;
      _playing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stopPlaying();
  }

  @override
  void dispose() {
    ++_requestVersion;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initialize() async {
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = false;
      _ready = false;
      _active = [];
      _excluded = [];
      _selected = null;
    });
    try {
      await _repository.initialize();
      if (!mounted || version != _requestVersion) return;
      _ready = true;
      await _setYear(_year);
    } catch (_) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _stopPlaying() {
    _timer?.cancel();
    _timer = null;
    if (_playing && mounted) setState(() => _playing = false);
  }

  Future<bool> _setYear(int next, {bool keepPlaying = false}) async {
    if (!territoryValidYear(next) || !_ready) return false;
    if (!keepPlaying) _stopPlaying();
    final version = ++_requestVersion;
    setState(() {
      _year = next;
      _loading = true;
      _error = false;
      _active = [];
      _excluded = [];
      _selected = null;
    });
    try {
      final data = await _repository.loadYear(next);
      if (!mounted || version != _requestVersion) return false;
      setState(() {
        _active = data.active;
        _excluded = data.excluded;
        _loading = false;
      });
      return true;
    } catch (_) {
      if (!mounted || version != _requestVersion) return false;
      _stopPlaying();
      setState(() {
        _loading = false;
        _error = true;
      });
      return false;
    }
  }

  int? _change(bool forward) {
    for (final year
        in forward ? _repository.changes : _repository.changes.reversed) {
      if (forward ? year > _year : year < _year) return year;
    }
    return null;
  }

  Future<void> _tick() async {
    if (!_playing || !mounted) return;
    final next = _change(true);
    if (next == null) {
      _stopPlaying();
      return;
    }
    final success = await _setYear(next, keepPlaying: true);
    if (mounted && _playing && success) {
      _timer = Timer(const Duration(milliseconds: 1800), _tick);
    }
  }

  void _togglePlaying() {
    if (_playing) {
      _stopPlaying();
      return;
    }
    if (!_ready || _loading || _error || _change(true) == null) return;
    setState(() => _playing = true);
    _timer = Timer(const Duration(milliseconds: 900), _tick);
  }

  Future<void> _jumpToYear() async {
    _stopPlaying();
    final result = await showDialog<int>(
      context: context,
      builder: (context) => _YearDialog(year: _year),
    );
    if (result != null && mounted) await _setYear(result);
  }

  void _selectFeature(TerritoryFeature feature) {
    _stopPlaying();
    setState(() => _selected = _selected?.id == feature.id ? null : feature);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final timeline = widget.dynasties.where(
      (r) => (r['start'] as num) <= _year && (r['end'] as num) >= _year,
    );
    return SingleChildScrollView(
      key: const PageStorageKey('territory-scroll'),
      padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 16, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('疆域随时间', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text('秦至清 · 前221—1911 · 从并立的政权，看历史的分与合'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xfff1ecdf),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Color(0xff8a6b44),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '这是来源区间筛选器，不是逐年复原。每年可选，但轮廓仅随来源记录变化；没有插值，也不用相邻年份填补缺失疆域。',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _mapCard()),
                    const SizedBox(width: 20),
                    SizedBox(width: 300, child: _polityPanel()),
                  ],
                )
              else ...[
                _mapCard(),
                const SizedBox(height: 16),
                _polityPanel(),
              ],
              const SizedBox(height: 18),
              _section('本年资料与缺漏', [
                if (_loading)
                  Text('正在读取${territoryYearText(_year)}的来源记录…')
                else if (_error)
                  const Text('加载失败，当前不显示疆域。年表对照仍可阅读。请重试后再判断数据覆盖。')
                else ...[
                  Text(
                    '已绘 ${_active.length} 条来源记录。轮廓取自各自的多年区间，不表示这些边界在本年都已被精确核实。',
                  ),
                  const SizedBox(height: 10),
                  ..._repository
                      .warnings(_year, _active, _excluded)
                      .map(
                        (text) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('• $text'),
                        ),
                      ),
                ],
              ]),
              const SizedBox(height: 16),
              _section('同期年表对照（${timeline.length}）', [
                const Text('年表收录与地图来源不同。列出的政权不一定有可绘制的独立轮廓。'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: timeline
                      .map(
                        (r) => Chip(
                          label: Text(
                            '${r['name']} · ${_period((r['start'] as num).toInt(), (r['end'] as num).toInt())}',
                          ),
                        ),
                      )
                      .toList(),
                ),
              ]),
              const SizedBox(height: 16),
              _section('来源、许可与方法', [
                const Text(
                  'Cliopatria / Seshat Global History Databank，固定版本 v0.2.1，CC BY 4.0。选取132个原始名称、877条 POLITY 区间记录；添加中文名称、配色、世纪分片及已知问题说明。保留来源坐标、字段、编号和日期，不按现代国界裁切，不以 Wikidata 身份自动替换。',
                ),
                const SizedBox(height: 10),
                const Text(
                  '底图为 Natural Earth 1:110m Land（公共领域）的现代陆地轮廓，不是古代海岸线，也没有现代国界。墨卡托投影的屏幕面积不可作为真实面积比较。多边形可以重叠，颜色不是排他的主权判定。',
                ),
                const SizedBox(height: 10),
                const Text(
                  '源研究通常排除面积不足5,000平方公里或存续不足50年的政权（有例外），且未编码边界不确定性。本版还存在选取范围的遗漏；没有颜色不代表政权不存在。',
                ),
                const SizedBox(height: 8),
                const Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _SourceLink(label: '固定版本数据', url: territorySourceUrl),
                    _SourceLink(
                      label: 'CC BY 4.0 许可',
                      url: 'https://creativecommons.org/licenses/by/4.0/',
                    ),
                    _SourceLink(
                      label: '研究与方法',
                      url: 'https://doi.org/10.1038/s41597-025-04516-9',
                    ),
                    _SourceLink(
                      label: 'Natural Earth 许可',
                      url:
                          'https://www.naturalearthdata.com/about/terms-of-use/',
                    ),
                  ],
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapCard() => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Wrap(
            spacing: 16,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                territoryYearText(_year),
                key: const Key('territory-year'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                _loading
                    ? '正在读取资料'
                    : _error
                    ? '此年数据未加载'
                    : '${_active.length} 条来源记录 · 区间示意',
              ),
            ],
          ),
        ),
        SizedBox(
          height: MediaQuery.sizeOf(context).width < 600 ? 340 : 480,
          child: Stack(
            children: [
              Positioned.fill(
                child: _TerritoryMap(
                  land: _repository.land,
                  active: _active,
                  selectedId: _selected?.id,
                  label: _repository.label,
                  color: _repository.color,
                  onSelected: _selectFeature,
                ),
              ),
              if (_loading || _error)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0xece7efec),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_loading) ...[
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              const Text('正在读取来源记录'),
                            ] else ...[
                              const Icon(Icons.cloud_off_outlined, size: 36),
                              const SizedBox(height: 12),
                              const Text(
                                '资料未能载入，当前没有绘制疆域。',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: () =>
                                    _ready ? _setYear(_year) : _initialize(),
                                icon: const Icon(Icons.refresh),
                                label: const Text('重新加载'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '上一年',
                    onPressed: _ready && _year > territoryMinimumYear
                        ? () => _setYear(
                            territorySliderYear(territoryYearSlider(_year) - 1),
                          )
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Slider(
                      key: const Key('territory-slider'),
                      min: territoryMinimumYear.toDouble(),
                      max: (territoryMaximumYear - 1).toDouble(),
                      divisions:
                          territoryMaximumYear - 1 - territoryMinimumYear,
                      value: territoryYearSlider(_year).toDouble(),
                      label: territoryYearText(_year),
                      semanticFormatterCallback: (value) =>
                          territoryYearText(territorySliderYear(value.round())),
                      onChanged: _ready
                          ? (value) =>
                                _setYear(territorySliderYear(value.round()))
                          : null,
                    ),
                  ),
                  IconButton(
                    tooltip: '下一年',
                    onPressed: _ready && _year < territoryMaximumYear
                        ? () => _setYear(
                            territorySliderYear(territoryYearSlider(_year) + 1),
                          )
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _ready && _change(false) != null
                        ? () => _setYear(_change(false)!)
                        : null,
                    icon: const Icon(Icons.skip_previous, size: 18),
                    label: const Text('上次变化'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed:
                        _playing ||
                            (_ready &&
                                !_loading &&
                                !_error &&
                                _change(true) != null)
                        ? _togglePlaying
                        : null,
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                    label: Text(_playing ? '暂停' : '播放变化'),
                  ),
                  TextButton.icon(
                    onPressed: _ready && _change(true) != null
                        ? () => _setYear(_change(true)!)
                        : null,
                    icon: const Icon(Icons.skip_next, size: 18),
                    label: const Text('下次变化'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _ready ? _jumpToYear : null,
                    icon: const Icon(Icons.edit_calendar, size: 18),
                    label: const Text('输入年份'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children:
                    [
                          -210,
                          100,
                          250,
                          500,
                          750,
                          950,
                          1100,
                          1142,
                          1320,
                          1400,
                          1750,
                        ]
                        .map(
                          (year) => ChoiceChip(
                            label: Text(_shortYear(year)),
                            selected: _year == year,
                            onSelected: _ready ? (_) => _setYear(year) : null,
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 10),
              Text(
                '播放只跳到来源记录或审计区间的变化点，不生成虚构的年度轮廓。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            '疆域：Cliopatria / Seshat v0.2.1 · CC BY 4.0｜底图：Natural Earth · 公共领域\n中文标注与区间筛选由本项目加工；原始坐标未简化。',
            style: TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );
  Widget _polityPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_selected != null) ...[
        _detail(_selected!),
        const SizedBox(height: 12),
      ],
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '本年来源记录 · ${_active.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 6),
              if (!_loading && !_error && _active.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('本版在此年没有可绘制记录。请查看年表对照与缺漏提示。'),
                ),
              ..._active.map(
                (f) => ListTile(
                  selected: _selected?.id == f.id,
                  leading: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _repository.color(f.name),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  title: Text(_repository.label(f.name)),
                  subtitle: Text('来源时段 ${_period(f.from, f.to)}'),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _selectFeature(f),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
  Widget _detail(TerritoryFeature f) {
    final identity = _map(_map(_repository.audit['identities'])[f.name]);
    final ranges = _list(identity['canonicalRanges']);
    final note = identity['note'] ?? identity['chronologyNote'];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _repository.label(f.name),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '取消选中',
                  onPressed: () => setState(() => _selected = null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text('来源原名：${f.name}'),
            const SizedBox(height: 12),
            Text('这块轮廓对应来源区间：${_period(f.from, f.to)}'),
            const SizedBox(height: 8),
            Text(
              '当前筛选${territoryYearText(_year)}。此区间内沿用同一来源轮廓，不能据此推断逐年的真实边界变化。',
            ),
            if (ranges.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '年表纪年参考：${ranges.map((r) => _period((r[0] as num).toInt(), (r[1] as num).toInt())).join('；')}。年表区间不是这块轮廓的有效性认证。',
              ),
            ],
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(note.toString()),
            ],
            if (f.properties['MemberOf'] != null &&
                f.properties['MemberOf'].toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '原数据关系字段：${f.properties['MemberOf']}。仅保留来源记录，不代表本版认定的直接统治关系。',
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '固定来源记录 #${f.id} · Cliopatria v0.2.1 · POLITY',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const _SourceLink(label: '查看固定版本来源', url: territorySourceUrl),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

class _YearDialog extends StatefulWidget {
  const _YearDialog({required this.year});
  final int year;
  @override
  State<_YearDialog> createState() => _YearDialogState();
}

class _YearDialogState extends State<_YearDialog> {
  late final TextEditingController _controller;
  late bool _bce;
  String? _error;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.year.abs()}');
    _bce = widget.year < 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final absolute = int.tryParse(_controller.text.trim());
    final year = (absolute ?? 0) * (_bce ? -1 : 1);
    if (absolute == null || absolute <= 0 || !territoryValidYear(year)) {
      setState(() => _error = '请输入前221年至1911年内的整数，没有公元0年。');
      return;
    }
    Navigator.pop(context, year);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('跳转年份'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('公元前')),
            ButtonSegment(value: false, label: Text('公元')),
          ],
          selected: {_bce},
          onSelectionChanged: (value) => setState(() => _bce = value.first),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: '年份',
            errorText: _error,
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('查看')),
    ],
  );
}

class _SourceLink extends StatelessWidget {
  const _SourceLink({required this.label, required this.url});
  final String label, url;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.open_in_new, size: 15),
    label: Text(label),
    onPressed: () async {
      bool opened;
      try {
        opened = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        opened = false;
      }
      if (!opened && context.mounted) {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('来源链接'),
            content: SelectableText('$label\n$url'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    },
  );
}

/// Painting and hit testing share one inverse transform. Drag/pinch owns only
/// the map viewport; ordinary page scrolling remains available outside it.
class _TerritoryMap extends StatefulWidget {
  const _TerritoryMap({
    required this.land,
    required this.active,
    required this.selectedId,
    required this.label,
    required this.color,
    required this.onSelected,
  });
  final List<TerritoryGeometry> land;
  final List<TerritoryFeature> active;
  final int? selectedId;
  final String Function(String) label;
  final Color Function(String) color;
  final ValueChanged<TerritoryFeature> onSelected;
  @override
  State<_TerritoryMap> createState() => _TerritoryMapState();
}

class _TerritoryMapState extends State<_TerritoryMap> {
  double _zoom = 1, _gestureZoom = 1;
  Offset _translation = Offset.zero, _gestureAnchor = Offset.zero;
  Size _size = Size.zero;
  bool _labels = true;
  final FocusNode _focus = FocusNode();
  double get _fit => math.min(_size.width / 1000, _size.height / 780);
  double get _scale => _fit * _zoom;
  Offset get _padding =>
      Offset((_size.width - 1000 * _fit) / 2, (_size.height - 780 * _fit) / 2);
  Offset get _origin => _padding + _translation;
  Offset _toWorld(Offset point) => (point - _origin) / _scale;
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _changeZoom(double factor, [Offset? focalPoint]) {
    if (_fit <= 0) return;
    final focal = focalPoint ?? _size.center(Offset.zero),
        world = _toWorld(focalPoint ?? _size.center(Offset.zero));
    setState(() {
      _zoom = (_zoom * factor).clamp(.35, 6.0);
      _translation = focal - _padding - world * _scale;
    });
  }

  void _reset() => setState(() {
    _zoom = 1;
    _translation = Offset.zero;
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _size = constraints.biggest;
      return Focus(
        focusNode: _focus,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.equal ||
              key == LogicalKeyboardKey.add) {
            _changeZoom(1.25);
          } else if (key == LogicalKeyboardKey.minus ||
              key == LogicalKeyboardKey.numpadSubtract) {
            _changeZoom(.8);
          } else if (key == LogicalKeyboardKey.home) {
            _reset();
          } else if (key == LogicalKeyboardKey.arrowLeft) {
            setState(() => _translation += const Offset(40, 0));
          } else if (key == LogicalKeyboardKey.arrowRight) {
            setState(() => _translation -= const Offset(40, 0));
          } else if (key == LogicalKeyboardKey.arrowUp) {
            setState(() => _translation += const Offset(0, 40));
          } else if (key == LogicalKeyboardKey.arrowDown) {
            setState(() => _translation -= const Offset(0, 40));
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                label: '疆域示意图。可拖动和双指缩放。下方列表提供全部来源记录及详情。',
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Listener(
                    onPointerSignal: (signal) {
                      if (signal is PointerScrollEvent &&
                          (HardwareKeyboard.instance.isControlPressed ||
                              HardwareKeyboard.instance.isMetaPressed)) {
                        GestureBinding.instance.pointerSignalResolver.register(
                          signal,
                          (event) {
                            _changeZoom(
                              signal.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15,
                              signal.localPosition,
                            );
                          },
                        );
                      }
                    },
                    child: GestureDetector(
                      key: const Key('territory-map'),
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (details) {
                        _focus.requestFocus();
                        _gestureZoom = _zoom;
                        _gestureAnchor = _toWorld(details.localFocalPoint);
                      },
                      onScaleUpdate: (details) => setState(() {
                        _zoom = (_gestureZoom * details.scale).clamp(.35, 6.0);
                        _translation =
                            details.localFocalPoint -
                            _padding -
                            _gestureAnchor * _scale;
                      }),
                      onTapUp: (details) {
                        _focus.requestFocus();
                        final point = _toWorld(details.localPosition);
                        for (final f in widget.active.reversed) {
                          if (f.geometry.bounds.contains(point) &&
                              f.geometry.path.contains(point)) {
                            widget.onSelected(f);
                            return;
                          }
                        }
                      },
                      child: RepaintBoundary(
                        child: CustomPaint(
                          key: const Key('territory-canvas'),
                          painter: _MapPainter(
                            land: widget.land,
                            active: widget.active,
                            selectedId: widget.selectedId,
                            label: widget.label,
                            color: widget.color,
                            scale: _scale,
                            origin: _origin,
                            labels: _labels,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              top: 12,
              left: 14,
              child: IgnorePointer(
                child: Text(
                  '↑ N',
                  style: TextStyle(color: Color(0xff668274), fontSize: 13),
                ),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 8,
              child: FilledButton.tonalIcon(
                onPressed: () => setState(() => _labels = !_labels),
                icon: Icon(_labels ? Icons.label : Icons.label_off, size: 16),
                label: Text('名称 ${_labels ? '开' : '关'}'),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 8,
              child: Card(
                margin: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '放大地图',
                      onPressed: () => _changeZoom(1.35),
                      icon: const Icon(Icons.add),
                    ),
                    IconButton(
                      tooltip: '缩小地图',
                      onPressed: () => _changeZoom(1 / 1.35),
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      tooltip: '重置地图',
                      onPressed: _reset,
                      icon: const Icon(Icons.center_focus_strong),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.land,
    required this.active,
    required this.selectedId,
    required this.label,
    required this.color,
    required this.scale,
    required this.origin,
    required this.labels,
  });
  final List<TerritoryGeometry> land;
  final List<TerritoryFeature> active;
  final int? selectedId;
  final String Function(String) label;
  final Color Function(String) color;
  final double scale;
  final Offset origin;
  final bool labels;
  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawColor(const Color(0xffe7efec), BlendMode.src);
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    final visible = Rect.fromPoints(
      -origin / scale,
      (size.bottomRight(Offset.zero) - origin) / scale,
    );
    final fill = Paint()..color = const Color(0xffe3e0d2);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7 / scale
      ..color = const Color(0xffc6cbbc);
    for (final geometry in land) {
      if (!geometry.bounds.overlaps(visible)) continue;
      canvas.drawPath(geometry.path, fill);
      canvas.drawPath(geometry.path, stroke);
    }
    final grid = Paint()
      ..color = const Color(0x507e9b8f)
      ..strokeWidth = .5 / scale;
    for (var lon = 0; lon <= 180; lon += 10) {
      canvas.drawLine(
        territoryProject([lon, -10]),
        territoryProject([lon, 78]),
        grid,
      );
    }
    for (var lat = 0; lat <= 70; lat += 10) {
      canvas.drawLine(
        territoryProject([0, lat]),
        territoryProject([180, lat]),
        grid,
      );
    }
    for (final f in active) {
      if (!f.geometry.bounds.overlaps(visible)) continue;
      final selected = selectedId == f.id;
      canvas.drawPath(
        f.geometry.path,
        Paint()
          ..color = color(f.name).withValues(
            alpha: selected
                ? .95
                : selectedId != null
                ? .28
                : .7,
          ),
      );
      canvas.drawPath(
        f.geometry.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = (selected ? 2 : .8) / scale
          ..color = selected
              ? const Color(0xff3e382c)
              : const Color(0xfffff9ec),
      );
    }
    canvas.restore();
    if (labels) {
      final occupied = <Rect>[];
      for (final f in active) {
        final center = f.geometry.labelPoint;
        if (center == null || f.geometry.labelArea < 700) continue;
        final point = center * scale + origin;
        final name = label(f.name).replaceAll(RegExp(r'〔.*?〕|（.*?）'), '');
        final text = TextPainter(
          text: TextSpan(
            text: name,
            style: const TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xff394135),
              shadows: [
                Shadow(color: Color(0xfffffaf0), blurRadius: 3),
                Shadow(color: Color(0xfffffaf0), blurRadius: 3),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 140);
        final bounds = Rect.fromCenter(
          center: point,
          width: text.width + 6,
          height: text.height + 6,
        );
        if (!(Offset.zero & size).contains(bounds.topLeft) ||
            !(Offset.zero & size).contains(bounds.bottomRight) ||
            occupied.any((rect) => rect.overlaps(bounds))) {
          continue;
        }
        occupied.add(bounds);
        text.paint(canvas, point - Offset(text.width / 2, text.height / 2));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      !identical(land, old.land) ||
      !identical(active, old.active) ||
      selectedId != old.selectedId ||
      scale != old.scale ||
      origin != old.origin ||
      labels != old.labels;
}
