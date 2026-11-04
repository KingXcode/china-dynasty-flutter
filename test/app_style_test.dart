import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huaxia_timeline/app_style.dart';

void main() {
  double contrast(Color foreground, Color background) {
    final a = foreground.computeLuminance();
    final b = background.computeLuminance();
    return (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
  }

  test('semantic text colors meet WCAG AA normal-text contrast', () {
    for (final background in [AppColors.surface, AppColors.canvas]) {
      for (final foreground in [
        AppColors.ink,
        AppColors.secondary,
        AppColors.subtle,
        AppColors.accent,
      ]) {
        expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
      }
    }
    expect(contrast(AppColors.ink, AppColors.mint), greaterThanOrEqualTo(4.5));
    expect(
      contrast(const Color(0xffc0d1c6), AppColors.dock),
      greaterThanOrEqualTo(4.5),
    );
  });

  for (final width in [320.0, 390.0, 1200.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('adaptive dock at $width px and ${scale}x text', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();

        try {
          await tester.pumpWidget(_DockHarness(scale: scale));
          await tester.pumpAndSettle();
          final dock = find.byType(AppNavigationDock);
          expect(dock, findsOneWidget);
          expect(tester.takeException(), isNull);
          final labels = find.descendant(of: dock, matching: find.text('历史脉络'));
          final label = tester.widget<Text>(labels);
          expect(label.textScaler!.scale(13), 13 * scale);
          expect(
            tester.getSemantics(find.bySemanticsLabel('历史脉络')),
            matchesSemantics(
              label: '历史脉络',
              hint: CupertinoLocalizations.of(tester.element(dock))
                  .tabSemanticsLabel(tabIndex: 1, tabCount: 2),
              isButton: true,
              isSelected: true,
              hasSelectedState: true,
              hasTapAction: true,
            ),
          );
          await tester.tap(find.text('疆域地图'));
          await tester.pumpAndSettle();
          expect(find.text('地图内容'), findsOneWidget);
          await tester.tap(find.text('历史脉络'));
          await tester.pumpAndSettle();
          expect(find.text('打开详情'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets(
    'dock retains Cupertino navigation stacks across repeated switches',
    (tester) async {
      await tester.pumpWidget(const _DockHarness());
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();
      expect(find.text('详情内容'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('疆域地图'));
        await tester.pumpAndSettle();
        expect(find.text('地图内容'), findsOneWidget);
        await tester.tap(find.text('历史脉络'));
        await tester.pumpAndSettle();
        expect(find.text('详情内容'), findsOneWidget);
      }
      await tester.tap(find.text('关闭详情'));
      await tester.pumpAndSettle();
      expect(find.text('打开详情'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _DockHarness extends StatelessWidget {
  const _DockHarness({this.scale = 1});
  final double scale;
  @override
  Widget build(BuildContext context) => CupertinoApp(
    home: CupertinoTabScaffold(
      tabBar: AppNavigationDock(
        textScaler: TextScaler.linear(scale),
        height: 84 + (13 * scale - 13),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.clock),
            label: '历史脉络',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.map),
            label: '疆域地图',
          ),
        ],
      ),
      tabBuilder: (context, index) => CupertinoTabView(
        builder: (context) => CupertinoPageScaffold(
          child: Center(
            child: index == 1
                ? const Text('地图内容')
                : CupertinoButton(
                    onPressed: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (context) => CupertinoPageScaffold(
                          child: Column(
                            children: [
                              const Text('详情内容'),
                              CupertinoButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('关闭详情'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    child: const Text('打开详情'),
                  ),
          ),
        ),
      ),
    ),
  );
}
