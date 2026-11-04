// Optional visual snapshots: flutter test test/render_test.dart --update-goldens
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huaxia_timeline/history.dart';
import 'package:huaxia_timeline/main.dart';
import 'package:huaxia_timeline/territory.dart';

void main() {
  final data = HistoryData(
    jsonDecode(File('assets/history.json').readAsStringSync())
        as Map<String, dynamic>,
    currentYear: 2026,
  );
  for (final width in [390.0, 1200.0]) {
    testWidgets('Render native timeline and map at $width px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fonts = FontLoader('NotoSansSC')
        ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Subset.otf'));
      await fonts.load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
      final repository = _SnapshotRepository();
      await tester.runAsync(repository.prime);
      await tester.pumpWidget(
        HuaxiaApp(data: data, territoryRepository: repository),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(HuaxiaApp),
        matchesGoldenFile('../qa/timeline-${width.toInt()}.png'),
      );
      await tester.tap(find.text('疆域地图').last);
      await tester.pump();
      // AssetBundle decodes large GeoJSON in a real isolate, outside FakeAsync.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pumpAndSettle();
      expect(find.text('华夏脉络'), findsOneWidget);
      await expectLater(
        find.byType(HuaxiaApp),
        matchesGoldenFile('../qa/territory-${width.toInt()}.png'),
      );
    }, skip: !const bool.fromEnvironment('RENDER_SNAPSHOTS'));
  }
}

// Real bundled geometry, preloaded outside FakeAsync solely for stable goldens.
// Async initialization/error/race behavior is independently exercised in territory_test.
class _SnapshotRepository extends TerritoryRepository {
  TerritoryYearData? loaded;
  Future<void> prime() async {
    await super.initialize();
    loaded = await super.loadYear(1142);
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<TerritoryYearData> loadYear(int year) =>
      year == 1142 ? Future.value(loaded!) : super.loadYear(year);
}
