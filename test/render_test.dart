// Optional visual snapshots: flutter test test/render_test.dart --update-goldens
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huaxia_timeline/history.dart';
import 'package:huaxia_timeline/main.dart';

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
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await tester.pumpWidget(HuaxiaApp(data: data));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(HuaxiaApp),
        matchesGoldenFile('../qa/timeline-${width.toInt()}.png'),
      );
      await tester.tap(find.text('疆域随时间').last);
      await tester.pump();
      // AssetBundle decodes large GeoJSON in a real isolate, outside FakeAsync.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(HuaxiaApp),
        matchesGoldenFile('../qa/territory-${width.toInt()}.png'),
      );
    }, skip: !const bool.fromEnvironment('RENDER_SNAPSHOTS'));
  }
}
