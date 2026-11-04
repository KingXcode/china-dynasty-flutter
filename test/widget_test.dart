import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huaxia_timeline/history.dart';
import 'package:huaxia_timeline/main.dart';
import 'package:huaxia_timeline/app_style.dart';

void main() {
  final data = HistoryData(
    jsonDecode(File('assets/history.json').readAsStringSync())
        as Map<String, dynamic>,
    currentYear: 2026,
  );
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets('Cupertino shell, search and details at $width px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(HuaxiaApp(data: data));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoApp), findsOneWidget);
      expect(find.byType(AppNavigationDock), findsOneWidget);
      expect(find.text('华夏脉络'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(CupertinoSearchTextField), '中华民国');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('中华民国（大陆时期）').first);
      await tester.tap(find.text('中华民国（大陆时期）').first);
      await tester.pumpAndSettle();
      expect(find.text('纪年说明'), findsOneWidget);
      expect(find.textContaining('迁至台湾'), findsOneWidget);
      if (width < 1000) {
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
        expect(find.text('纪年说明'), findsNothing);
      }
      tester
          .widget<CupertinoSearchTextField>(
            find.byType(CupertinoSearchTextField),
          )
          .onSuffixTap!();
      await tester.pumpAndSettle();
      expect(find.text('全局主线'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Cupertino era picker and display sheet preserve actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(HuaxiaApp(data: data));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全局主线'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    await tester.tap(find.text('秦汉'));
    await tester.pumpAndSettle();
    expect(find.text('秦汉'), findsOneWidget);
    expect(find.byType(CupertinoActionSheet), findsNothing);
    await tester.tap(find.byIcon(CupertinoIcons.slider_horizontal_3));
    await tester.pumpAndSettle();
    expect(find.text('显示设置'), findsOneWidget);
    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.textContaining('等比例刻度 ·'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('200 percent text has no overflow in Cupertino timeline', (
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
    await tester.tap(find.text('年代表'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
