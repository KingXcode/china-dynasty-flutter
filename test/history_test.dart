import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:huaxia_timeline/history.dart';
import 'package:huaxia_timeline/timeline.dart';

void main() {
  late HistoryData data;
  setUp(
    () => data = HistoryData(
      jsonDecode(File('assets/history.json').readAsStringSync())
          as Map<String, dynamic>,
      currentYear: 2026,
    ),
  );
  test('102 original records, 56 sources and 13 eras remain complete', () {
    expect(data.dynasties.length, 102);
    expect(data.sources.length, 56);
    expect(data.eras.length, 13);
    expect(data.dynasties.map((r) => r['id']).toSet().length, 102);
    for (final d in data.dynasties) {
      expect(d['start'], isNot(0));
      expect(d['end'], isNot(0));
      expect(d['start'] as int, lessThan(d['end'] as int));
      for (final source in d['sourceIds'] as List) {
        expect(data.sources.any((s) => s['id'] == source), isTrue);
      }
    }
    expect(
      data.dynasties.where((d) => d['traditionalSixteen'] == true).length,
      16,
    );
    expect(data.dynasties.where((d) => d['group'] == 'five').length, 5);
    expect(data.dynasties.where((d) => d['group'] == 'ten').length, 10);
  });
  test('no year zero, modern period clarification and ongoing year', () {
    expect(yearSpan(-1, 1), 1);
    expect(yearSpan(-206, 9), 214);
    expect(yearText(-221), '前221');
    final roc = data.dynasties.firstWhere((d) => d['id'] == 'roc');
    expect(roc['name'], '中华民国（大陆时期）');
    expect(roc['end'], 1949);
    expect(roc['ongoing'], isNot(true));
    expect(roc['note'], contains('迁至台湾'));
    expect(roc['note'], contains('继续'));
    final changed = HistoryData(
      jsonDecode(File('assets/history.json').readAsStringSync())
          as Map<String, dynamic>,
      currentYear: 2030,
    );
    expect(changed.dynasties.firstWhere((d) => d['id'] == 'prc')['end'], 2030);
    expect(changed.dynasties.firstWhere((d) => d['id'] == 'roc')['end'], 1949);
  });
  test('search is global, era filtering includes concurrent powers', () {
    expect(data.filter(query: '中华民国').single['id'], 'roc');
    expect(
      data.filter(era: 'overview').length,
      data.dynasties.where((d) => d['core'] == true).length,
    );
    expect(data.filter(era: 'all').length, 102);
    expect(
      data.filter(era: 'songyuan').map((d) => d['id']),
      containsAll(['liao', 'northern-song', 'southern-song', 'jin-jurchen']),
    );
    expect(
      data.filter(era: 'regional').every((d) => d['group'] == 'regional'),
      true,
    );
    final song = data.dynasties.firstWhere((d) => d['id'] == 'northern-song');
    expect(data.contemporaries(song).map((d) => d['id']), contains('liao'));
  });
  for (final width in [288.0, 343.0, 358.0, 398.0, 1060.0]) {
    for (final exact in [false, true]) {
      test(
        'timeline at $width px exact=$exact shares monotone year mapping and fits labels',
        () {
          final records = data.filter(era: 'all');
          final layout = TimelineLayout(
            records: records,
            exact: exact,
            zoom: 1,
            width: width,
          );
          expect(layout.labelX, lessThan(width - 120));
          expect(layout.items.length, 102);
          double last = -1;
          for (final event in layout.events) {
            expect(layout.y(event), greaterThan(last));
            last = layout.y(event);
          }
          for (var i = 1; i < layout.items.length; i++) {
            expect(
              layout.items[i].labelY,
              greaterThanOrEqualTo(
                layout.items[i - 1].labelY + layout.labelHeight,
              ),
            );
          }
          for (final item in layout.items) {
            expect(layout.y(item.start), lessThan(layout.y(item.end)));
            expect(52 + item.lane * layout.laneStep, lessThan(layout.labelX));
            for (final other in layout.items.where(
              (r) => r.lane == item.lane && r != item,
            )) {
              expect(
                item.start < other.end && other.start < item.end,
                isFalse,
                reason: 'Concurrent records must not share a track',
              );
            }
          }
          if (exact) {
            expect(layout.y(1949) - layout.y(1912), closeTo(37 * 1.2, .001));
          }
        },
      );
    }
  }
}
