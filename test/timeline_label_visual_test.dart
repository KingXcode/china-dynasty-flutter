// Optional snapshots: flutter test test/timeline_label_visual_test.dart
//   --dart-define=RENDER_SNAPSHOTS=true --update-goldens
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huaxia_timeline/history.dart';
import 'package:huaxia_timeline/main.dart';
import 'package:huaxia_timeline/timeline.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('Render simplified modern details at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'NotoSansSC',
      )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Subset.otf'))).load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(
            rootBundle.load(
              'packages/cupertino_icons/assets/CupertinoIcons.ttf',
            ),
          ))
          .load();
      final data = HistoryData(
        jsonDecode(File('assets/history.json').readAsStringSync())
            as Map<String, dynamic>,
        currentYear: 2026,
      );
      await tester.pumpWidget(HuaxiaApp(data: data));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoSearchTextField), '中华民国');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('中华民国').last);
      await tester.tap(find.text('中华民国').last);
      await tester.pumpAndSettle();
      expect(find.byType(DynastyDetailsBody), findsOneWidget);
      expect(find.textContaining('大陆时期'), findsNothing);
      expect(find.text('纪年说明'), findsNothing);
      expect(find.text('参考来源'), findsNothing);
      await expectLater(
        find.byType(HuaxiaApp),
        matchesGoldenFile('../qa/modern-details-${width.toInt()}.png'),
      );
      expect(tester.takeException(), isNull);
    }, skip: !const bool.fromEnvironment('RENDER_SNAPSHOTS'));
  }
}
