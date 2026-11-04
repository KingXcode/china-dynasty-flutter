import 'dart:convert';
import 'package:flutter/services.dart';

/// Historical years use -1, 1 without a year zero.
int ordinal(int year) => year < 0 ? year + 1 : year;
int yearSpan(int start, int end) => ordinal(end) - ordinal(start);
String yearText(int year) => year < 0 ? '前${-year}' : '$year';
String dateRange(Map<String, dynamic> record) =>
    '${record['approximate'] == true ? '约 ' : ''}${yearText(record['start'] as int)} — ${record['ongoing'] == true ? '至今' : yearText(record['end'] as int)}';

class HistoryData {
  HistoryData(Map<String, dynamic> data, {int? currentYear})
    : sources = List<Map<String, dynamic>>.from(data['sources'] as List),
      eras = List<Map<String, dynamic>>.from(data['eras'] as List),
      traditions = List<Map<String, dynamic>>.from(data['traditions'] as List),
      meta = Map<String, dynamic>.from(data['meta'] as Map),
      dynasties = (data['dynasties'] as List).map((raw) {
        final record = Map<String, dynamic>.from(raw as Map);
        if (record['ongoing'] == true) {
          record['end'] = currentYear ?? DateTime.now().year;
        }
        return record;
      }).toList() {
    for (final era in eras) {
      if (era['id'] == 'modern') {
        era['end'] = currentYear ?? DateTime.now().year;
      }
    }
  }
  final List<Map<String, dynamic>> sources, eras, traditions, dynasties;
  final Map<String, dynamic> meta;
  static Future<HistoryData> load() async => HistoryData(
    jsonDecode(await rootBundle.loadString('assets/history.json'))
        as Map<String, dynamic>,
  );
  String groupName(String id) =>
      eras.where((e) => e['id'] == id).firstOrNull?['name'] as String? ?? id;
  List<Map<String, dynamic>> filter({
    String era = 'overview',
    String query = '',
  }) {
    final q = query.trim().toLowerCase();
    final selectedEra = eras.where((e) => e['id'] == era).firstOrNull;
    final selected = dynasties.where((d) {
      if (q.isNotEmpty) {
        return [
          d['name'],
          d['english'],
          d['region'],
          d['note'],
          groupName(d['group'] as String),
          ...(d['aliases'] as List? ?? []),
        ].join(' ').toLowerCase().contains(q);
      }
      if (era == 'overview') return d['core'] == true;
      if (era == 'regional') return d['group'] == 'regional';
      if (selectedEra == null) return true;
      return (d['start'] as int) < (selectedEra['end'] as int) &&
          (d['end'] as int) > (selectedEra['start'] as int);
    }).toList();
    selected.sort((a, b) {
      final order = (a['start'] as int).compareTo(b['start'] as int);
      if (order != 0) return order;
      final core = (b['core'] == true ? 1 : 0).compareTo(
        a['core'] == true ? 1 : 0,
      );
      return core != 0 ? core : (b['end'] as int).compareTo(a['end'] as int);
    });
    return selected;
  }

  List<Map<String, dynamic>> contemporaries(Map<String, dynamic> d) => dynasties
      .where(
        (r) =>
            r['id'] != d['id'] &&
            (r['start'] as int) < (d['end'] as int) &&
            (r['end'] as int) > (d['start'] as int),
      )
      .toList();
}
