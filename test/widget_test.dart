import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huaxia_timeline/history.dart';
import 'package:huaxia_timeline/main.dart';

void main() {
  final data = HistoryData(
    jsonDecode(File('assets/history.json').readAsStringSync())
        as Map<String, dynamic>,
    currentYear: 2026,
  );
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets('responsive shell, search and details at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(HuaxiaApp(data: data));
      await tester.pumpAndSettle();
      expect(find.text('华夏脉络'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField).first, '中华民国');
      await tester.pumpAndSettle();
      expect(find.text('中华民国（大陆时期）'), findsOneWidget);
      await tester.ensureVisible(find.text('中华民国（大陆时期）'));
      await tester.tap(find.text('中华民国（大陆时期）'));
      await tester.pumpAndSettle();
      expect(find.text('纪年说明'), findsOneWidget);
      expect(find.textContaining('迁至台湾'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭详情'));
      await tester.pumpAndSettle();
      expect(find.text('纪年说明'), findsNothing);
      await tester.ensureVisible(find.byTooltip('清除搜索'));
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      expect(find.text('一览华夏，纵贯古今'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('200 percent text has no overflow and can switch to table', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(HuaxiaApp(data: data));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('年代表'));
    await tester.tap(find.text('年代表'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
