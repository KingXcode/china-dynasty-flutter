// Bundled Cliopatria source intervals, never an interpolated yearly reconstruction.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_style.dart';

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

Map<String, dynamic> _decodeTerritoryJson(String source) =>
    _map(jsonDecode(source));

class _TerritoryRecord {
  _TerritoryRecord(Map<String, dynamic> json)
    : id = (json['id'] as num).toInt(),
      properties = _map(json['properties']),
      geometry = _map(json['geometry']);
  final int id;
  final Map<String, dynamic> properties, geometry;
  late final String name = properties['Name'] as String;
  late final int from = (properties['FromYear'] as num).toInt();
  late final int to = (properties['ToYear'] as num).toInt();
}

/// Resolved, bounded caches make warm scrubs synchronous. In-flight reads are
/// separate from the LRU so eviction cannot duplicate a still-running request.
/// Year results share a source interval (including canonical acceptance changes),
/// never an invented or interpolated boundary.
class TerritoryRepository {
  TerritoryRepository({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;
  final LinkedHashMap<int, List<_TerritoryRecord>> _shards = LinkedHashMap();
  final Map<int, Future<List<_TerritoryRecord>>> _pendingShards = {};
  final LinkedHashMap<int, TerritoryYearData> _years = LinkedHashMap();
  final Map<int, Future<TerritoryYearData>> _pendingYears = {};
  final LinkedHashMap<int, TerritoryFeature> _features = LinkedHashMap();
  Map<String, dynamic> names = {}, audit = {};
  List<int> changes = [];
  List<TerritoryGeometry> land = [];
  final Map<String, Color> _colors = {};
  Future<Map<String, dynamic>> _read(String file) async {
    final source = await _bundle.loadString(
      'assets/map-data/$file',
      cache: false,
    );
    // Native Android/iOS decode off the UI isolate. On Web, cold work is
    // coalesced by the scrub scheduler; compute uses the current event loop.
    return compute(_decodeTerritoryJson, source);
  }

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
    land = _list(data[3]['features'])
        .map((row) => TerritoryGeometry.fromJson(_map(row['geometry'])))
        .toList();
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
  Future<List<_TerritoryRecord>> _loadCentury(int century) {
    final cached = _shards.remove(century);
    if (cached != null) {
      _shards[century] = cached;
      return Future.value(cached);
    }
    return _pendingShards.putIfAbsent(century, () async {
      try {
        final data = await _read('era-$century.geojson');
        final records = _list(data['features'])
            .map((row) => _TerritoryRecord(_map(row)))
            .toList(growable: false);
        _shards[century] = records;
        while (_shards.length > 4) {
          _shards.remove(_shards.keys.first);
        }
        return records;
      } finally {
        _pendingShards.remove(century); // Failed reads remain retryable.
      }
    });
  }

  int _intervalKey(int year) {
    // Every source FromYear/ToYear+1 and canonical acceptance boundary is in
    // changes. Warnings and chronology text are evaluated for the exact year.
    var low = 0, high = changes.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (changes[middle] <= year) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low == 0 ? year : changes[low - 1];
  }

  TerritoryYearData _rememberYear(int year, TerritoryYearData data) {
    final key = _intervalKey(year);
    _years.remove(key);
    _years[key] = data;
    while (_years.length > 96) {
      _years.remove(_years.keys.first);
    }
    return data;
  }

  /// No I/O, futures, or geometry projection in a pointer-event cache hit.
  TerritoryYearData? cachedYear(int year) {
    if (!territoryValidYear(year)) return null;
    final key = _intervalKey(year);
    final cached = _years.remove(key);
    if (cached != null) {
      _years[key] = cached;
      return cached;
    }
    final century = territoryCentury(year);
    final records = _shards.remove(century);
    if (records == null) return null;
    _shards[century] = records;
    final active = <TerritoryFeature>[], excluded = <TerritoryFeature>[];
    for (final record in records) {
      if (record.from > year ||
          record.to < year ||
          !names.containsKey(record.name)) {
        continue;
      }
      final feature = _features[record.id];
      if (feature == null) return null;
      (territoryAcceptedAt(record.name, year, audit) ? active : excluded).add(
        feature,
      );
    }
    active.sort((a, b) => b.area.compareTo(a.area));
    return _rememberYear(year, TerritoryYearData(active, excluded));
  }

  Future<TerritoryYearData> loadYear(int year) {
    if (!territoryValidYear(year)) {
      return Future.error(ArgumentError.value(year, 'year'));
    }
    final cached = cachedYear(year);
    if (cached != null) return Future.value(cached);
    final key = _intervalKey(year);
    return _pendingYears.putIfAbsent(key, () async {
      try {
        final records = await _loadCentury(territoryCentury(year));
        final active = <TerritoryFeature>[], excluded = <TerritoryFeature>[];
        final work = Stopwatch()..start();
        for (final record in records) {
          if (record.from > year ||
              record.to < year ||
              !names.containsKey(record.name)) {
            continue;
          }
          final feature =
              _features.remove(record.id) ??
              TerritoryFeature(
                record.id,
                record.properties,
                TerritoryGeometry.fromJson(record.geometry),
              );
          _features[record.id] = feature;
          (territoryAcceptedAt(record.name, year, audit) ? active : excluded)
              .add(feature);
          // Bound cold projection batches, allowing touch/paint between them.
          if (work.elapsedMilliseconds >= 4) {
            await Future<void>.delayed(Duration.zero);
            work.reset();
          }
        }
        while (_features.length > 160) {
          _features.remove(_features.keys.first);
        }
        active.sort((a, b) => b.area.compareTo(a.area));
        return _rememberYear(year, TerritoryYearData(active, excluded));
      } finally {
        _pendingYears.remove(key);
      }
    });
  }

  /// Called only after an idle pause, never once per slider tick. Prefetch
  /// failures are quiet and evicted; a later foreground load can retry.
  Future<void> prefetchAdjacent(int year) async {
    final century = territoryCentury(year);
    for (final next in [century - 100, century + 100]) {
      if (next < territoryCentury(territoryMinimumYear) ||
          next > territoryCentury(territoryMaximumYear)) {
        continue;
      }
      try {
        await _loadCentury(next);
      } catch (_) {
        // Optional warmup must not change the displayed year's error state.
      }
    }
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
      if (_list(gap['missingSourceIntervals'])
          .any((range) => _inRange(year, _list(range)))) {
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
  int? _displayedYear, _loadingYear;
  bool _ready = false, _loading = true, _error = false, _playing = false;
  bool _showWarnings = false, _showMethod = false;
  List<TerritoryFeature> _active = [], _excluded = [];
  TerritoryFeature? _selected;
  Timer? _timer, _scrubTimer, _prefetchTimer;
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
    _scrubTimer?.cancel();
    _prefetchTimer?.cancel();
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
      _displayedYear = null;
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

  void _warmNearby(int year) {
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted && _year == year && !_loading) {
        unawaited(_repository.prefetchAdjacent(year));
      }
    });
  }

  void _commitYear(int year, TerritoryYearData data) {
    setState(() {
      _year = year;
      _displayedYear = year;
      _active = data.active;
      _excluded = data.excluded;
      _selected = null;
      _loading = false;
      _loadingYear = null;
      _error = false;
    });
    _warmNearby(year);
  }

  void _scrubYear(double value) {
    final next = territorySliderYear(value.round());
    if (!territoryValidYear(next) || !_ready || next == _year) return;
    _stopPlaying();
    _scrubTimer?.cancel();
    _prefetchTimer?.cancel();
    final version = ++_requestVersion; // Invalidate old success AND old errors.
    _loadingYear = null;
    final cached = _repository.cachedYear(next);
    if (cached != null) {
      _commitYear(next, cached);
      return;
    }
    setState(() {
      _year = next;
      _loading = true;
      _error = false;
    });
    // Move the thumb immediately; only load the final cold target after the
    // user's brief pause. onChangeEnd flushes without waiting for this timer.
    _scrubTimer = Timer(const Duration(milliseconds: 90), () {
      _scrubTimer = null;
      unawaited(_loadYear(next, version));
    });
  }

  Future<bool> _setYear(int next, {bool keepPlaying = false}) async {
    if (!territoryValidYear(next) || !_ready) return false;
    if (!keepPlaying) _stopPlaying();
    _scrubTimer?.cancel();
    _scrubTimer = null;
    _prefetchTimer?.cancel();
    if (!_error &&
        (_displayedYear == next && !_loading ||
            _loadingYear == next && _year == next)) {
      return true;
    }
    final version = ++_requestVersion;
    final cached = _repository.cachedYear(next);
    if (cached != null) {
      _commitYear(next, cached);
      return true;
    }
    setState(() {
      _year = next;
      _loading = true;
      _error = false;
    });
    return _loadYear(next, version);
  }

  Future<bool> _loadYear(int next, int version) async {
    _loadingYear = next;
    try {
      final data = await _repository.loadYear(next);
      if (!mounted || version != _requestVersion) return false;
      _commitYear(next, data);
      return true;
    } catch (_) {
      if (!mounted || version != _requestVersion) return false;
      _stopPlaying();
      setState(() {
        _loading = false;
        _loadingYear = null;
        _error = true;
        _active = [];
        _excluded = [];
        _selected = null;
        _displayedYear = null;
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
    final result = await showCupertinoDialog<int>(
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
    final shownYear = _displayedYear ?? _year;
    final timeline = widget.dynasties.where(
      (r) => (r['start'] as num) <= shownYear && (r['end'] as num) >= shownYear,
    );
    return DefaultTextStyle.merge(
      style: TextStyle(fontSize: 15, height: 1.35, color: AppColors.ink),
      child: SingleChildScrollView(
        key: const PageStorageKey('territory-scroll'),
        padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 12, wide ? 28 : 16, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppPageIntro(
                  index: '02 / 山河探索',
                  title: '山河之间',
                  subtitle: '拖动年份，探索疆域资料。秦至清 · 前221—1911',
                ),
                const SizedBox(height: 18),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _mapCard()),
                      const SizedBox(width: 20),
                      SizedBox(width: 320, child: _polityPanel()),
                    ],
                  )
                else
                  _mapCard(),
                const SizedBox(height: 14),
                _section('资料提示 · ${territoryYearText(shownYear)}', [
                  if (_loading && _displayedYear == null)
                    Text('正在读取${territoryYearText(_year)}的来源记录…')
                  else if (_error)
                    const Text('加载失败，当前不显示疆域。年表仍可阅读，请重试后再判断资料覆盖。')
                  else ...[
                    Text(
                      _excluded.isNotEmpty
                          ? '${_excluded.length} 条记录因纪年冲突未绘制。缺失疆域没有用其他年份补齐。'
                          : '${_active.length} 条来源记录。轮廓取自多年区间，并非本年全部边界已经核实。',
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.only(top: 8),
                      alignment: Alignment.centerLeft,
                      minimumSize: const Size(44, 32),
                      onPressed: () =>
                          setState(() => _showWarnings = !_showWarnings),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _showWarnings ? '收起缺漏说明' : '查看缺漏与纪年说明',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            _showWarnings
                                ? CupertinoIcons.chevron_up
                                : CupertinoIcons.chevron_down,
                            size: 12,
                          ),
                        ],
                      ),
                    ),
                    if (_showWarnings)
                      ..._repository
                          .warnings(shownYear, _active, _excluded)
                          .map(
                            (text) => Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                '• $text',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                  ],
                ]),
                if (!wide) ...[const SizedBox(height: 14), _polityPanel()],
                const SizedBox(height: 14),
                _section(
                  '${territoryYearText(shownYear)} · 同期年表 ${timeline.length}',
                  [
                    Text(
                      '年表与地图来源不同，以下政权不一定有独立轮廓。',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...timeline.map(
                      (record) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(
                          '${record['name']}  ${_period((record['start'] as num).toInt(), (record['end'] as num).toInt())}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _section('来源与方法', [
                  const Text(
                    '这是来源区间筛选器，不是逐年疆域复原。没有插值或形变补间。',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Cliopatria / Seshat v0.2.1 · CC BY 4.0\nNatural Earth 1:110m Land · 公共领域',
                    style: TextStyle(fontSize: 13),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.only(top: 8),
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size(44, 32),
                    onPressed: () => setState(() => _showMethod = !_showMethod),
                    child: Text(
                      _showMethod ? '收起数据说明' : '阅读完整数据说明',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  if (_showMethod) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '固定来源选取132个原始名称、877条 POLITY 区间记录，添加中文名称、配色、世纪分片及问题提示。原始坐标、字段、编号和日期保留，不按现代国界裁切，不以 Wikidata 身份自动替换。',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '底图为现代陆地轮廓，不是古代海岸线，没有现代国界。墨卡托投影的屏幕面积不可作为真实面积比较。多边形可以重叠，颜色不是排他的主权判定。',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '源研究通常排除面积不足5,000平方公里或存续不足50年的政权（有例外），且未编码边界不确定性。本版还存在选取范围的遗漏；没有颜色不代表政权不存在。',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                  const SizedBox(height: 6),
                  const Wrap(
                    spacing: 16,
                    runSpacing: 2,
                    children: [
                      _SourceLink(label: '固定版本', url: territorySourceUrl),
                      _SourceLink(
                        label: 'CC BY 4.0',
                        url: 'https://creativecommons.org/licenses/by/4.0/',
                      ),
                      _SourceLink(
                        label: '研究方法',
                        url: 'https://doi.org/10.1038/s41597-025-04516-9',
                      ),
                      _SourceLink(
                        label: '底图许可',
                        url: 'https://www.naturalearthdata.com/about/terms-of-use/',
                      ),
                    ],
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseEra() async {
    _stopPlaying();
    final next = await showCupertinoModalPopup<int>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择参考年份'),
        message: const Text('所示为来源区间，不代表完整年度疆域。'),
        actions: [
          for (final entry in const <int, String>{
            -210: '秦朝 · 前210',
            100: '汉代 · 100',
            250: '三国 · 250',
            500: '南北朝 · 500',
            750: '唐代 · 750',
            950: '五代十国 · 950',
            1100: '北宋 · 1100',
            1142: '宋金并立 · 1142',
            1320: '元代 · 1320',
            1400: '明代 · 1400',
            1750: '清代 · 1750',
          }.entries)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(entry.value),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
    if (next != null && mounted) await _setYear(next);
  }

  Widget _mapCard() => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  onPressed: _ready ? _jumpToYear : null,
                  child: Text(
                    territoryYearText(_displayedYear ?? _year),
                    key: const Key('territory-year'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
              _MapIconButton(
                label: '输入年份',
                icon: CupertinoIcons.calendar,
                onPressed: _ready ? _jumpToYear : null,
              ),
            ],
          ),
        ),
        SizedBox(
          height: MediaQuery.sizeOf(context).width < 600
              ? (MediaQuery.sizeOf(context).height * .36).clamp(250.0, 320.0)
              : 450,
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
              if (_loading && _displayedYear != null)
                Positioned(
                  top: 8,
                  left: 10,
                  right: 10,
                  child: IgnorePointer(
                    child: Semantics(
                      liveRegion: true,
                      child: Container(
                        key: const Key('territory-pending'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: .96),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Text(
                          '正在切换至${territoryYearText(_year)} · 地图仍为${territoryYearText(_displayedYear!)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if ((_loading && _displayedYear == null) || _error)
                Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.canvas.withValues(alpha: .96),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_loading) ...[
                              const CupertinoActivityIndicator(radius: 12),
                              const SizedBox(height: 12),
                              const Text('正在读取来源记录'),
                            ] else ...[
                              const Icon(
                                CupertinoIcons.exclamationmark_circle,
                                size: 30,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                '资料未能载入，当前没有绘制疆域。',
                                textAlign: TextAlign.center,
                              ),
                              CupertinoButton(
                                onPressed: () =>
                                    _ready ? _setYear(_year) : _initialize(),
                                child: const Text('重新加载'),
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
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Row(
            children: [
              _MapIconButton(
                label: '上一年',
                icon: CupertinoIcons.chevron_left,
                onPressed: _ready && _year > territoryMinimumYear
                    ? () => _setYear(
                        territorySliderYear(territoryYearSlider(_year) - 1),
                      )
                    : null,
              ),
              Expanded(
                child: Semantics(
                  label: territoryYearText(_year),
                  child: CupertinoSlider(
                    key: const Key('territory-slider'),
                    min: territoryMinimumYear.toDouble(),
                    max: (territoryMaximumYear - 1).toDouble(),
                    divisions: territoryMaximumYear - 1 - territoryMinimumYear,
                    value: territoryYearSlider(_year).toDouble(),
                    onChangeStart: _ready ? (_) => _stopPlaying() : null,
                    onChanged: _ready ? _scrubYear : null,
                    onChangeEnd: _ready
                        ? (value) =>
                              _setYear(territorySliderYear(value.round()))
                        : null,
                  ),
                ),
              ),
              _MapIconButton(
                label: '下一年',
                icon: CupertinoIcons.chevron_right,
                onPressed: _ready && _year < territoryMaximumYear
                    ? () => _setYear(
                        territorySliderYear(territoryYearSlider(_year) + 1),
                      )
                    : null,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              _MapIconButton(
                label: '上次变化',
                icon: CupertinoIcons.backward_end,
                onPressed: _ready && _change(false) != null
                    ? () => _setYear(_change(false)!)
                    : null,
              ),
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  onPressed:
                      _playing ||
                          (_ready &&
                              !_loading &&
                              !_error &&
                              _change(true) != null)
                      ? _togglePlaying
                      : null,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _playing
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        size: 17,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          _playing ? '暂停' : '播放变化',
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _MapIconButton(
                label: '下次变化',
                icon: CupertinoIcons.forward_end,
                onPressed: _ready && _change(true) != null
                    ? () => _setYear(_change(true)!)
                    : null,
              ),
              _MapIconButton(
                label: '选择时代',
                icon: CupertinoIcons.ellipsis_circle,
                onPressed: _ready ? _chooseEra : null,
              ),
            ],
          ),
        ),
        const _Hairline(),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
          child: Text(
            _loading
                ? _displayedYear == null
                      ? '正在读取来源区间'
                      : '目标 ${territoryYearText(_year)} · 保留上一幅地图'
                : _error
                ? '当前资料未加载'
                : '${_active.length} 条来源记录 · 非逐年复原',
            style: TextStyle(fontSize: 12, color: AppColors.secondary),
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
        const SizedBox(height: 14),
      ],
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                '${_displayedYear == null ? '本年' : territoryYearText(_displayedYear!)}来源记录 · ${_active.length}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!_loading && !_error && _active.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('本版在此年没有可绘制记录。请查看年表对照与缺漏提示。'),
              ),
            for (var i = 0; i < _active.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.only(left: 44),
                  child: _Hairline(),
                ),
              CupertinoListTile(
                key: ValueKey('territory-record-${_active[i].id}'),
                backgroundColor: _selected?.id == _active[i].id
                    ? AppColors.accentSoft
                    : null,
                leading: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _repository.color(_active[i].name),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                title: Text(
                  _repository.label(_active[i].name),
                  maxLines: 3,
                  style: const TextStyle(fontSize: 15),
                ),
                subtitle: Text(
                  '来源 ${_period(_active[i].from, _active[i].to)}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const CupertinoListTileChevron(),
                onTap: () => _selectFeature(_active[i]),
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _detail(TerritoryFeature feature) {
    final identity = _map(_map(_repository.audit['identities'])[feature.name]);
    final ranges = _list(identity['canonicalRanges']);
    final note = identity['note'] ?? identity['chronologyNote'];
    return _section(
      _repository.label(feature.name),
      [
        Text(
          '来源原名：${feature.name}',
          style: TextStyle(fontSize: 13, color: AppColors.secondary),
        ),
        const SizedBox(height: 12),
        Text(
          '来源区间：${_period(feature.from, feature.to)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          '当前地图${territoryYearText(_displayedYear ?? _year)}。此区间内沿用同一来源轮廓，不能据此推断逐年真实边界。',
          style: const TextStyle(fontSize: 14),
        ),
        if (ranges.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '年表参考：${ranges.map((r) => _period((r[0] as num).toInt(), (r[1] as num).toInt())).join('；')}。年表区间不是轮廓有效性的认证。',
            style: const TextStyle(fontSize: 14),
          ),
        ],
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(note.toString(), style: const TextStyle(fontSize: 14)),
        ],
        if (feature.properties['MemberOf'] != null &&
            feature.properties['MemberOf'].toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '原数据关系：${feature.properties['MemberOf']}。仅保留来源记录，不代表本版认定的直接统治关系。',
            style: const TextStyle(fontSize: 14),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          '固定来源 #${feature.id} · Cliopatria v0.2.1 · POLITY',
          style: TextStyle(fontSize: 12, color: AppColors.secondary),
        ),
        const _SourceLink(label: '查看固定版本来源', url: territorySourceUrl),
      ],
      trailing: _MapIconButton(
        label: '取消选中',
        icon: CupertinoIcons.xmark_circle_fill,
        onPressed: () => setState(() => _selected = null),
      ),
    );
  }

  Widget _section(String title, List<Widget> children, {Widget? trailing}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (trailing == null)
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  trailing,
                ],
              ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      );
}

class _Hairline extends StatelessWidget {
  const _Hairline();
  @override
  Widget build(BuildContext context) =>
      Container(height: .5, color: AppColors.line);
}

class _MapIconButton extends StatelessWidget {
  const _MapIconButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    enabled: onPressed != null,
    child: CupertinoButton(
      padding: const EdgeInsets.all(10),
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: ExcludeSemantics(child: Icon(icon, size: 21)),
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
  Widget build(BuildContext context) => CupertinoAlertDialog(
    title: const Text('跳转年份'),
    content: Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          CupertinoSlidingSegmentedControl<bool>(
            groupValue: _bce,
            children: const {
              true: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('公元前'),
              ),
              false: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('公元'),
              ),
            },
            onValueChanged: (value) {
              if (value != null) setState(() => _bce = value);
            },
          ),
          const SizedBox(height: 14),
          CupertinoTextField(
            controller: _controller,
            autofocus: true,
            placeholder: '年份',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _submit(),
            padding: const EdgeInsets.all(12),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: CupertinoColors.systemRed,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      CupertinoDialogAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      CupertinoDialogAction(
        isDefaultAction: true,
        onPressed: _submit,
        child: const Text('查看'),
      ),
    ],
  );
}

class _SourceLink extends StatelessWidget {
  const _SourceLink({required this.label, required this.url});
  final String label, url;
  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: const EdgeInsets.symmetric(vertical: 6),
    minimumSize: const Size(44, 32),
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, style: const TextStyle(fontSize: 13))),
        const SizedBox(width: 5),
        const Icon(CupertinoIcons.arrow_up_right, size: 12),
      ],
    ),
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
        showCupertinoDialog<void>(
          context: context,
          builder: (context) => CupertinoAlertDialog(
            title: const Text('来源链接'),
            content: Text('$label\n$url'),
            actions: [
              CupertinoDialogAction(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('复制链接'),
              ),
              CupertinoDialogAction(
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
  final Map<String, TextPainter> _labelPainters = {};
  double get _fit => math.min(_size.width / 1000, _size.height / 780);
  double get _scale => _fit * _zoom;
  Offset get _padding =>
      Offset((_size.width - 1000 * _fit) / 2, (_size.height - 780 * _fit) / 2);
  Offset get _origin => _padding + _translation;
  Offset _toWorld(Offset point) => (point - _origin) / _scale;
  @override
  void dispose() {
    _focus.dispose();
    for (final painter in _labelPainters.values) {
      painter.dispose();
    }
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
                            labelPainters: _labelPainters,
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
              bottom: 10,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xeeffffff),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: _MapIconButton(
                  label: _labels ? '隐藏名称' : '显示名称',
                  icon: _labels
                      ? CupertinoIcons.textformat
                      : CupertinoIcons.textformat_alt,
                  onPressed: () => setState(() => _labels = !_labels),
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xeeffffff),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MapIconButton(
                      label: '放大地图',
                      icon: CupertinoIcons.plus,
                      onPressed: () => _changeZoom(1.35),
                    ),
                    const SizedBox(width: 30, child: _Hairline()),
                    _MapIconButton(
                      label: '缩小地图',
                      icon: CupertinoIcons.minus,
                      onPressed: () => _changeZoom(1 / 1.35),
                    ),
                    const SizedBox(width: 30, child: _Hairline()),
                    _MapIconButton(
                      label: '重置地图',
                      icon: CupertinoIcons.location,
                      onPressed: _reset,
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
    required this.labelPainters,
  });
  final List<TerritoryGeometry> land;
  final List<TerritoryFeature> active;
  final int? selectedId;
  final String Function(String) label;
  final Color Function(String) color;
  final double scale;
  final Offset origin;
  final bool labels;
  final Map<String, TextPainter> labelPainters;
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
        final text = labelPainters.putIfAbsent(
          name,
          () => TextPainter(
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
          )..layout(maxWidth: 140),
        );
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
