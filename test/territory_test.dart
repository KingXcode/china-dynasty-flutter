import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huaxia_timeline/territory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('BCE century floor and no-year-zero slider are exact inverses', () {
    expect(territoryCentury(-1), -100);
    expect(territoryCentury(-101), -200);
    expect(territoryCentury(1), 0);
    expect(territorySliderYear(-1), -1);
    expect(territorySliderYear(0), 1);
    expect(territoryValidYear(0), isFalse);
    expect(territoryValidYear(-222), isFalse);
    for (int slider = -221; slider <= 1910; slider++) {
      final year = territorySliderYear(slider);
      expect(year, isNot(0));
      expect(territoryValidYear(year), isTrue);
      expect(territoryYearSlider(year), slider);
    }
  });
  test('Change immediately after 1 BCE is included as 1 CE', () {
    final changes = territoryChanges([
      {'name': 'A', 'from': -2, 'to': -1},
    ], {});
    expect(changes, contains(1));
    expect(changes, isNot(contains(0)));
    expect(changes.first, -221);
    expect(changes.last, 1911);
  });
  test(
    'Polygon holes, multipolygons and projected hit tests preserve topology',
    () {
      final geometry = TerritoryGeometry.fromJson({
        'type': 'Polygon',
        'coordinates': [
          [
            [100, 20],
            [120, 20],
            [120, 40],
            [100, 40],
            [100, 20],
          ],
          [
            [105, 25],
            [115, 25],
            [115, 35],
            [105, 35],
            [105, 25],
          ],
        ],
      });
      expect(geometry.path.fillType, PathFillType.evenOdd);
      expect(geometry.path.contains(territoryProject([102, 22])), isTrue);
      expect(geometry.path.contains(territoryProject([110, 30])), isFalse);
      expect(geometry.path.contains(territoryProject([130, 30])), isFalse);
      expect(geometry.labelPoint, isNull);
      final multi = TerritoryGeometry.fromJson({
        'type': 'MultiPolygon',
        'coordinates': [
          [
            [
              [100, 20],
              [104, 20],
              [104, 24],
              [100, 24],
              [100, 20],
            ],
          ],
          [
            [
              [120, 30],
              [124, 30],
              [124, 34],
              [120, 34],
              [120, 30],
            ],
          ],
        ],
      });
      expect(multi.path.contains(territoryProject([102, 22])), isTrue);
      expect(multi.path.contains(territoryProject([122, 32])), isTrue);
      expect(multi.path.contains(territoryProject([112, 27])), isFalse);
      expect(territoryProject([180, 90]).dy.isFinite, isTrue);
    },
  );
  test('Bundled source integrity and key concurrent regimes', () async {
    final repository = TerritoryRepository();
    await repository.initialize();
    expect(repository.names.length, 132);
    final index = jsonDecode(
      await rootBundle.loadString('assets/map-data/index.json'),
    );
    expect(index['records'].length, 877);
    for (final fixture in <int, List<String>>{
      250: ['Cao Wei', 'Shu Han', 'Eastern Wu'],
      500: ['Northern Wei', 'Southern Qi'],
      1142: [
        'Southern Song',
        'Great Jin',
        'Western Xia',
        'Kingdom of Dali',
        'Kara-Khitans',
      ],
      1750: ['Qing Dynasty', 'Dzungar Khanate'],
    }.entries) {
      final data = await repository.loadYear(fixture.key);
      expect(data.active.map((f) => f.name), containsAll(fixture.value));
      for (final feature in data.active) {
        expect(feature.activeAt(fixture.key), isTrue);
        expect(feature.activeAt(feature.from), isTrue);
        expect(feature.activeAt(feature.to), isTrue);
      }
    }
    for (final fixture in <int, String>{
      421: 'Western Jin',
      1130: 'Northern Song',
      1369: 'Yuan Dynasty',
      1644: 'Later Jin Dynasty',
      224: 'Han Dynasty',
      695: 'Tang Dynasty',
    }.entries) {
      final data = await repository.loadYear(fixture.key);
      expect(data.active.map((f) => f.name), isNot(contains(fixture.value)));
      expect(data.excluded.map((f) => f.name), contains(fixture.value));
      expect(
        repository.warnings(fixture.key, data.active, data.excluded).join(),
        contains('不绘制'),
      );
    }
    expect(
      (await repository.loadYear(-221)).active.map((f) => f.name),
      isNot(contains('Qin Dynasty')),
    );
    expect(
      (await repository.loadYear(-210)).active.map((f) => f.name),
      contains('Qin Dynasty'),
    );
    expect(repository.label('Western Jin'), contains('未分西晋/东晋'));
    expect(repository.label('Han Dynasty'), contains('来源统称'));
  });
  test('Failed shard is evicted and retry can succeed', () async {
    final bundle = _FailOnceBundle();
    final repository = TerritoryRepository(bundle: bundle);
    await repository.initialize();
    await expectLater(repository.loadYear(250), throwsA(isA<StateError>()));
    final loaded = await repository.loadYear(250);
    expect(loaded.active, isNotEmpty);
    expect(bundle.failures, 1);
  });
  testWidgets(
    'Latest year wins over stale async data; failures clear old polygons',
    (tester) async {
      final repository = _ControlledRepository();
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: TerritoryPage(dynasties: const [], repository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('公元 1142 年'), findsOneWidget);
      final first = Completer<TerritoryYearData>(),
          latest = Completer<TerritoryYearData>();
      repository.pending[250] = first;
      repository.pending[500] = latest;
      tester
          .widget<CupertinoSlider>(find.byKey(const Key('territory-slider')))
          .onChanged!(249);
      await tester.pump();
      tester
          .widget<CupertinoSlider>(find.byKey(const Key('territory-slider')))
          .onChanged!(499);
      await tester.pump();
      latest.complete(TerritoryYearData([_feature('最新记录', 2)], []));
      await tester.pumpAndSettle();
      first.complete(TerritoryYearData([_feature('过期记录', 1)], []));
      await tester.pumpAndSettle();
      expect(find.text('公元 500 年'), findsOneWidget);
      expect(find.text('最新记录'), findsOneWidget);
      expect(find.text('过期记录'), findsNothing);
      final failed = Completer<TerritoryYearData>();
      repository.pending[750] = failed;
      tester
          .widget<CupertinoSlider>(find.byKey(const Key('territory-slider')))
          .onChanged!(749);
      await tester.pump();
      failed.completeError(StateError('test failure'));
      await tester.pumpAndSettle();
      expect(find.text('最新记录'), findsNothing);
      expect(find.text('重新加载'), findsOneWidget);
      expect(find.text('公元 750 年'), findsOneWidget);
    },
  );
  testWidgets('Map taps use inverse transform; drag and pinch never select', (
    tester,
  ) async {
    final feature = _feature('测试政权', 88);
    final repository = _ControlledRepository(initialFeatures: [feature]);
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: TerritoryPage(dynasties: const [], repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final map = find.byKey(const Key('territory-map'));
    final canvas = find.byKey(const Key('territory-canvas'));
    Offset featurePosition() {
      final dynamic painter = tester.widget<CustomPaint>(canvas).painter;
      return tester.getTopLeft(canvas) +
          (painter.origin as Offset) +
          feature.geometry.labelPoint! * (painter.scale as double);
    }

    await tester.tapAt(featurePosition());
    await tester.pumpAndSettle();
    expect(find.text('来源原名：测试政权'), findsOneWidget);
    await tester.tapAt(featurePosition());
    await tester.pumpAndSettle();
    expect(find.text('来源原名：测试政权'), findsNothing);
    await tester.dragFrom(featurePosition(), const Offset(55, 15));
    await tester.pumpAndSettle();
    expect(find.text('来源原名：测试政权'), findsNothing);
    await tester.tapAt(featurePosition());
    await tester.pumpAndSettle();
    expect(find.text('来源原名：测试政权'), findsOneWidget);
    await tester.tapAt(featurePosition());
    await tester.pumpAndSettle();
    final center = tester.getCenter(map);
    final first = await tester.startGesture(
      center - const Offset(45, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(45, 0),
      pointer: 2,
    );
    await first.moveBy(const Offset(-30, 0));
    await second.moveBy(const Offset(30, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(find.text('来源原名：测试政权'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Year input rejects zero and crosses directly from 1 BCE to 1 CE',
    (tester) async {
      final repository = _ControlledRepository();
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: TerritoryPage(dynasties: const [], repository: repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.bySemanticsLabel('输入年份'));
      await tester.tap(find.bySemanticsLabel('输入年份'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), '0');
      await tester.tap(find.text('查看'));
      await tester.pumpAndSettle();
      expect(find.text('请输入前221年至1911年内的整数，没有公元0年。'), findsOneWidget);
      await tester.tap(find.text('公元前'));
      await tester.enterText(find.byType(CupertinoTextField), '1');
      await tester.tap(find.text('查看'));
      await tester.pumpAndSettle();
      expect(find.text('公元前 1 年'), findsOneWidget);
      await tester.ensureVisible(find.bySemanticsLabel('下一年'));
      await tester.tap(find.bySemanticsLabel('下一年'));
      await tester.pumpAndSettle();
      expect(find.text('公元 1 年'), findsOneWidget);
      expect(repository.years, [1142, -1, 1]);
    },
  );
  testWidgets('Cupertino map and playback fit the 390px first screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          navigationBar: const CupertinoNavigationBar(middle: Text('疆域随时间')),
          child: SafeArea(
            child: TerritoryPage(
              dynasties: const [],
              repository: _ControlledRepository(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byKey(const Key('territory-map'))).height,
      greaterThanOrEqualTo(250),
    );
    expect(tester.getRect(find.text('播放变化')).bottom, lessThan(740));
    expect(find.byType(CupertinoSlider), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('选择时代'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('三国 · 250'));
    await tester.pumpAndSettle();
    expect(find.text('公元 250 年'), findsOneWidget);
  });
  testWidgets('Cupertino map, detail and year entry fit 390px at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      CupertinoApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: CupertinoPageScaffold(
          child: TerritoryPage(
            dynasties: const [],
            repository: _ControlledRepository(
              initialFeatures: [_feature('Western Jin', 77)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.bySemanticsLabel('输入年份'));
    await tester.tap(find.bySemanticsLabel('输入年份'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(CupertinoListTile).first);
    await tester.tap(find.byType(CupertinoListTile).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('查看缺漏与纪年说明'));
    await tester.tap(find.text('查看缺漏与纪年说明'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets('Territory layout fits $width px without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: TerritoryPage(
              dynasties: const [],
              repository: _ControlledRepository(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -1100),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Changing tab via TickerMode stops source-change playback', (
    tester,
  ) async {
    final repository = _ControlledRepository();
    Widget app(bool active) => CupertinoApp(
      home: CupertinoPageScaffold(
        child: TickerMode(
          enabled: active,
          child: TerritoryPage(dynasties: const [], repository: repository),
        ),
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('播放变化'));
    await tester.tap(find.text('播放变化'));
    await tester.pump();
    expect(find.text('暂停'), findsOneWidget);
    await tester.pumpWidget(app(false));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('暂停'), findsNothing);
    expect(repository.years, [1142]);
  });
}

class _FailOnceBundle extends CachingAssetBundle {
  int failures = 0;
  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('era-200.geojson') && failures == 0) {
      failures++;
      throw StateError('transient');
    }
    return rootBundle.load(key);
  }
}

TerritoryFeature _feature(String name, int id) => TerritoryFeature(
  id,
  {'Name': name, 'FromYear': 1, 'ToYear': 1911, 'Area': 1, 'Type': 'POLITY'},
  TerritoryGeometry.fromJson({
    'type': 'Polygon',
    'coordinates': [
      [
        [100, 20],
        [120, 20],
        [120, 40],
        [100, 40],
        [100, 20],
      ],
    ],
  }),
);

class _ControlledRepository extends TerritoryRepository {
  _ControlledRepository({this.initialFeatures = const []});
  final List<TerritoryFeature> initialFeatures;
  final Map<int, Completer<TerritoryYearData>> pending = {};
  final List<int> years = [];
  @override
  Future<void> initialize() async {
    changes = [-221, 250, 500, 750, 1142, 1200, 1911];
  }

  @override
  Future<TerritoryYearData> loadYear(int year) {
    years.add(year);
    return pending[year]?.future ??
        Future.value(TerritoryYearData(initialFeatures, []));
  }
}
