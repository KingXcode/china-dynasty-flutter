import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huaxia_timeline/desktop_timeline.dart';
import 'package:huaxia_timeline/history.dart';

Map<String, dynamic> record(
  String id,
  int start,
  int end, {
  bool core = true,
}) => {'id': id, 'name': id, 'start': start, 'end': end, 'core': core};

DesktopTimelineLayout layout(
  List<Map<String, dynamic>> records, {
  bool exact = true,
  int? start,
  int? end,
  double zoom = 1,
}) => DesktopTimelineLayout(
  records: records,
  allRecords: records,
  start: start,
  end: end,
  exact: exact,
  zoom: zoom,
);

void main() {
  test(
    'parallel tracks align dates and reserve label space, not fake duration',
    () {
      final graph = layout([
        record('Long', 200, 280),
        record('Short', 200, 201),
        record('Next', 202, 203),
        record('Later', 220, 240),
      ]);
      final long = graph.entries.firstWhere((e) => e.record['id'] == 'Long');
      final short = graph.entries.firstWhere((e) => e.record['id'] == 'Short');
      final next = graph.entries.firstWhere((e) => e.record['id'] == 'Next');
      expect(long.startY, short.startY);
      expect(long.lane, isNot(short.lane));
      expect(next.lane, isNot(short.lane));
      expect(short.endY - short.startY, graph.scale.pixelsPerYear);
      expect(short.reservedUntil - short.startY, 54);
      for (final a in graph.entries) {
        for (final b in graph.entries) {
          if (a == b || a.lane != b.lane || a.startY > b.startY) continue;
          expect(a.reservedUntil, lessThanOrEqualTo(b.startY + .00001));
        }
      }
      expect(short.x - long.x, 155);
    },
  );

  test('BCE and CE adjacent years are one historical year, never zero', () {
    final graph = layout([record('Crossing', -5, 5)]);
    expect(graph.scale.y(1) - graph.scale.y(-1), graph.scale.pixelsPerYear);
    expect(graph.scale.ticks, isNot(contains(0)));
    expect(graph.scale.folds, isEmpty);
    expect(graph.scale.y(5) - graph.scale.y(-5), 9 * graph.scale.pixelsPerYear);
  });

  test('compact folding is shared, monotonic, and contains no events', () {
    final records = [
      record('Early', -600, -500),
      record('Long', -600, 600),
      record('Late', 500, 600),
    ];
    final graph = layout(records, exact: false);
    expect(graph.scale.folds, isNotEmpty);
    final fold = graph.scale.folds.single;
    expect(fold.start, isNot(0));
    expect(fold.end, isNot(0));
    expect(
      graph.scale.y(fold.end) - graph.scale.y(fold.start),
      closeTo(38, .0001),
    );
    expect(graph.scale.y(-1), lessThan(graph.scale.y(1)));
    expect(graph.scale.ticks, isNot(contains(0)));
    for (final r in records) {
      for (final event in [r['start'] as int, r['end'] as int]) {
        expect(event > fold.start && event < fold.end, isFalse);
      }
    }
    final exact = layout(records);
    expect(exact.scale.folds, isEmpty);
    expect(exact.height, greaterThan(graph.height));
  });

  test('era bounds clip rails and retain actual label dates', () {
    final graph = layout(
      [record('Beyond', -100, 100), record('Inside', 20, 30)],
      start: 1,
      end: 50,
    );
    final clipped = graph.entries.first;
    expect(clipped.continuesBefore, isTrue);
    expect(clipped.continuesAfter, isTrue);
    expect(clipped.startY, graph.scale.y(1));
    expect(clipped.endY, graph.scale.y(50));
    expect(dateRange(clipped.record), '前100 — 100');
    expect(graph.entries.last.continuesBefore, isFalse);
    expect(graph.entries.last.continuesAfter, isFalse);
  });

  test(
    'colors keep original record order after filtering and support overrides',
    () {
      final records = [
        record('A', 1, 100),
        record('B', 30, 80),
        {...record('C', 40, 50), 'color': '#123456'},
      ];
      final graph = DesktopTimelineLayout(
        records: records.sublist(1),
        allRecords: records,
        exact: true,
        zoom: 1,
      );
      expect(graph.entries.first.color, const Color(0xff547b67));
      expect(graph.entries.last.color, const Color(0xff123456));
    },
  );

  test(
    'complete historical data has no lane-label collisions at every zoom',
    () {
      final data = HistoryData(
        jsonDecode(File('assets/history.json').readAsStringSync())
            as Map<String, dynamic>,
        currentYear: 2026,
      );
      for (final zoom in [.6, 1.0, 2.2]) {
        for (final exact in [false, true]) {
          final graph = layout(data.dynasties, exact: exact, zoom: zoom);
          expect(graph.entries.length, data.dynasties.length);
          expect(graph.laneCount, greaterThan(2));
          for (var lane = 0; lane < graph.laneCount; lane++) {
            final entries = graph.entries.where((e) => e.lane == lane).toList();
            for (var i = 1; i < entries.length; i++) {
              expect(
                entries[i].startY,
                greaterThanOrEqualTo(entries[i - 1].reservedUntil - .00001),
              );
            }
          }
        }
      }
    },
  );

  testWidgets(
    'bounded viewport scrolls both axes and selects with Cupertino buttons',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final records = List.generate(8, (i) => record('State $i', 100, 900 - i));
      Map<String, dynamic>? selected;
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 650,
                child: DesktopTimelineGraph(
                  records: records,
                  allRecords: records,
                  exact: true,
                  zoom: 1,
                  onSelected: (record) => selected = record,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.byKey(const ValueKey('desktop-timeline-viewport')))
            .height,
        620,
      );
      expect(find.byType(CupertinoButton), findsNWidgets(8));
      final vertical = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('desktop-timeline-vertical-scroll')),
          )
          .controller!;
      final horizontal = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('desktop-timeline-horizontal-scroll')),
          )
          .controller!;
      expect(vertical.position.maxScrollExtent, greaterThan(0));
      expect(horizontal.position.maxScrollExtent, greaterThan(0));
      await tester.tap(find.text('State 0'));
      await tester.pumpAndSettle();
      expect(selected?['id'], 'State 0');
      selected = null;
      final button = find.descendant(
        of: find.byKey(const ValueKey('desktop-record-State 1')),
        matching: find.byType(CupertinoButton),
      );
      final focus = Focus.of(
        tester.element(
          find.descendant(of: button, matching: find.byType(Text)).first,
        ),
      );
      focus.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected?['id'], 'State 1');
      horizontal.jumpTo(horizontal.position.maxScrollExtent);
      vertical.jumpTo(vertical.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selected semantics expose full dates and clipping', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final records = [record('王朝', -100, 100)];
    await tester.pumpWidget(
      CupertinoApp(
        home: SingleChildScrollView(
          child: DesktopTimelineGraph(
            records: records,
            allRecords: records,
            start: 1,
            end: 50,
            exact: false,
            zoom: 1,
            selectedId: '王朝',
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('王朝，前100 — 100。开始早于所选时代。结束晚于所选时代。查看详情'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('empty chart is useful and has no scroll exceptions', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: DesktopTimelineGraph(
          records: const [],
          allRecords: const [],
          exact: false,
          zoom: 1,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('没有符合条件的历史记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large accessibility text keeps readable labels without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final records = [record('前秦', 350, 394), record('北魏', 386, 534)];
      await tester.pumpWidget(
        CupertinoApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SingleChildScrollView(
              child: DesktopTimelineGraph(
                records: records,
                allRecords: records,
                exact: false,
                zoom: .6,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('optional desktop visual snapshot', (tester) async {
    tester.view.physicalSize = const Size(900, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader(
      'NotoSansSC',
    )..addFont(rootBundle.load('assets/fonts/NotoSansSC-Subset.otf'))).load();
    final data = HistoryData(
      jsonDecode(File('assets/history.json').readAsStringSync())
          as Map<String, dynamic>,
      currentYear: 2026,
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(
      CupertinoApp(
        theme: const CupertinoThemeData(
          textTheme: CupertinoTextThemeData(
            textStyle: TextStyle(fontFamily: 'NotoSansSC'),
          ),
        ),
        home: CupertinoPageScaffold(
          backgroundColor: const Color(0xfff2f2f7),
          child: RepaintBoundary(
            key: boundary,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: DesktopTimelineGraph(
                records: data.filter(era: 'division'),
                allRecords: data.dynasties,
                start: 220,
                end: 589,
                exact: false,
                zoom: 1,
                selectedId: 'cao-wei',
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('/tmp/desktop-timeline-cupertino.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  }, skip: !const bool.fromEnvironment('DESKTOP_SNAPSHOT'));
}
