import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huaxia_timeline/territory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Warm interval lookups are synchronous, stable, and do not read assets',
    () async {
      final bundle = _RecordingBundle();
      final repository = TerritoryRepository(bundle: bundle);
      await repository.initialize();
      expect(repository.cachedYear(1142), isNull);

      final initial = await repository.loadYear(1142);
      final reads = Map<String, int>.of(bundle.reads);
      // This interval is independently established by the fixed source index.
      // Different integer years do not imply different source geometries.
      for (var i = 0; i < 1000; i++) {
        final year = 1139 + i % 8;
        expect(repository.cachedYear(year), same(initial));
      }
      expect(await repository.loadYear(1146), same(initial));
      expect(bundle.reads, reads);
    },
  );

  test(
    'Resolved-century cache miss performs no new I/O or projection',
    () async {
      final bundle = _RecordingBundle();
      final repository = TerritoryRepository(bundle: bundle);
      await repository.initialize();
      await repository.loadYear(1142);
      final reads = Map<String, int>.of(bundle.reads);
      expect(repository.cachedYear(1100), isNull);
      expect(bundle.reads, reads);
      final other = await repository.loadYear(1100);
      expect(other.active.map((f) => f.name), contains('Northern Song'));
      expect(other.active.map((f) => f.name), isNot(contains('Southern Song')));
      expect(bundle.reads, reads);
      expect(repository.cachedYear(1100), same(other));
      expect(await repository.loadYear(1100), same(other));
    },
  );

  test(
    'Cold requests share a shard even with more than four in flight',
    () async {
      final bundle = _RecordingBundle();
      final repository = TerritoryRepository(bundle: bundle);
      await repository.initialize();
      const years = [-210, 250, 750, 1142, 1400, 1750];
      for (final year in years) {
        bundle.gates[_shardKey(year)] = Completer<void>();
      }
      final loads = [for (final year in years) repository.loadYear(year)];
      loads.add(repository.loadYear(251));
      await Future<void>.delayed(Duration.zero);
      for (final year in years) {
        expect(bundle.reads[_shardKey(year)], 1);
      }
      for (final gate in bundle.gates.values) {
        gate.complete();
      }
      final results = await Future.wait(loads);
      expect(results, hasLength(7));
      expect(results.last.active.every((f) => f.activeAt(251)), isTrue);
      expect(bundle.reads[_shardKey(250)], 1);
    },
  );

  test(
    'A failed shard leaves no synchronous false hit and can be retried',
    () async {
      final bundle = _RecordingBundle();
      final repository = TerritoryRepository(bundle: bundle);
      await repository.initialize();
      bundle.failNext.add(_shardKey(250));
      await expectLater(repository.loadYear(250), throwsA(isA<StateError>()));
      expect(repository.cachedYear(250), isNull);
      final recovered = await repository.loadYear(250);
      expect(recovered.active, isNotEmpty);
      expect(repository.cachedYear(250), same(recovered));
      expect(bundle.reads[_shardKey(250)], 2);
    },
  );

  test('Prefetch reads only the adjacent valid centuries', () async {
    final bundle = _RecordingBundle();
    final repository = TerritoryRepository(bundle: bundle);
    await repository.initialize();
    await repository.prefetchAdjacent(territoryMinimumYear);
    await repository.prefetchAdjacent(territoryMaximumYear);
    await repository.prefetchAdjacent(1142);
    final shardReads = bundle.reads.keys
        .where((key) => key.contains('/era-'))
        .toSet();
    expect(shardReads, {
      _shardKey(-200),
      _shardKey(1800),
      _shardKey(1000),
      _shardKey(1200),
    });
    expect(bundle.reads[_shardKey(1142)], isNull);
  });

  test('Foreground and prefetch share the same pending shard', () async {
    final bundle = _RecordingBundle();
    final repository = TerritoryRepository(bundle: bundle);
    await repository.initialize();
    final gate = Completer<void>();
    bundle.gates[_shardKey(1000)] = gate;
    final prefetch = repository.prefetchAdjacent(1142);
    final foreground = repository.loadYear(1050);
    await Future<void>.delayed(Duration.zero);
    expect(bundle.reads[_shardKey(1000)], 1);
    gate.complete();
    await prefetch;
    final loaded = await foreground;
    expect(loaded.active, isNotEmpty);
    expect(bundle.reads[_shardKey(1000)], 1);
  });

  test(
    'Prefetch failure is quiet, continues, and foreground can retry',
    () async {
      final bundle = _RecordingBundle();
      final repository = TerritoryRepository(bundle: bundle);
      await repository.initialize();
      bundle.failNext.add(_shardKey(1000));
      await repository.prefetchAdjacent(1142);
      expect(bundle.reads[_shardKey(1000)], 1);
      expect(bundle.reads[_shardKey(1200)], 1);
      expect(repository.cachedYear(1050), isNull);
      expect((await repository.loadYear(1050)).active, isNotEmpty);
      expect(bundle.reads[_shardKey(1000)], 2);
    },
  );

  test(
    'Interval keys preserve audit boundaries and the missing year zero',
    () async {
      final repository = TerritoryRepository(bundle: _AuditBoundaryBundle());
      await repository.initialize();
      final bce = await repository.loadYear(-1);
      final ce = await repository.loadYear(1);
      expect(bce.active.map((f) => f.id), [7]);
      expect(bce.excluded, isEmpty);
      expect(ce.active, isEmpty);
      expect(ce.excluded.map((f) => f.id), [7]);
      expect(ce, isNot(same(bce)));
      final accepted = repository.cachedYear(2)!;
      expect(accepted.active.map((f) => f.id), [7]);
      expect(accepted.excluded, isEmpty);
      expect(repository.cachedYear(3), same(accepted));
      final excluded = repository.cachedYear(4)!;
      expect(excluded.active, isEmpty);
      expect(excluded.excluded.map((f) => f.id), [7]);
      final ended = repository.cachedYear(7)!;
      expect(ended.active, isEmpty);
      expect(ended.excluded, isEmpty);
      await expectLater(repository.loadYear(0), throwsArgumentError);
    },
  );

  test('Every valid year matches independent original-source filtering; '
      'old distant intervals are evicted', () async {
    final bundle = _RecordingBundle();
    final repository = TerritoryRepository(bundle: bundle);
    await repository.initialize();
    final names = jsonDecode(
      await rootBundle.loadString('assets/map-data/polities.json'),
    ) as Map<String, dynamic>;
    final audit = jsonDecode(
      await rootBundle.loadString('assets/map-data/audit.json'),
    ) as Map<String, dynamic>;
    final identities = audit['identities'] as Map<String, dynamic>;
    final originals = <int, List<dynamic>>{};
    TerritoryYearData? first;
    for (
      var year = territoryMinimumYear;
      year <= territoryMaximumYear;
      year++
    ) {
      if (year == 0) continue;
      final century = territoryCentury(year);
      if (!originals.containsKey(century)) {
        final source = jsonDecode(
          await rootBundle.loadString(_shardKey(year)),
        ) as Map<String, dynamic>;
        originals[century] = source['features'] as List<dynamic>;
      }
      final expectedActive = <int>{}, expectedExcluded = <int>{};
      for (final dynamic raw in originals[century]!) {
        final row = raw as Map<String, dynamic>;
        final properties = row['properties'] as Map<String, dynamic>;
        final name = properties['Name'] as String;
        if (!names.containsKey(name) ||
            (properties['FromYear'] as num) > year ||
            (properties['ToYear'] as num) < year) {
          continue;
        }
        final identity = identities[name] as Map<String, dynamic>?;
        final ranges = identity?['canonicalRanges'] as List<dynamic>? ?? [];
        final accepted =
            ranges.isEmpty ||
            ranges.any(
              (dynamic range) =>
                  (range[0] as num) <= year && year <= (range[1] as num),
            );
        (accepted ? expectedActive : expectedExcluded).add(row['id'] as int);
      }
      final data = await repository.loadYear(year);
      first ??= data;
      expect(
        data.active.map((f) => f.id).toSet(),
        expectedActive,
        reason: 'Active source IDs at year $year',
      );
      expect(
        data.excluded.map((f) => f.id).toSet(),
        expectedExcluded,
        reason: 'Excluded source IDs at year $year',
      );
      expect(repository.cachedYear(year), same(data));
      for (var i = 1; i < data.active.length; i++) {
        expect(
          data.active[i - 1].area,
          greaterThanOrEqualTo(data.active[i].area),
        );
      }
    }
    // More than 96 source intervals and four centuries have been visited.
    // The first result must not be retained indefinitely by the repository.
    expect(repository.cachedYear(territoryMinimumYear), isNull);
    final reload = await repository.loadYear(territoryMinimumYear);
    expect(reload, isNot(same(first)));
    expect(
      reload.active.map((f) => f.id).toSet(),
      first!.active.map((f) => f.id).toSet(),
    );
    expect(bundle.reads[_shardKey(territoryMinimumYear)], 2);
  });
}

String _shardKey(int year) =>
    'assets/map-data/era-${territoryCentury(year)}.geojson';

class _RecordingBundle extends CachingAssetBundle {
  final reads = <String, int>{};
  final gates = <String, Completer<void>>{};
  final failNext = <String>{};

  @override
  Future<ByteData> load(String key) async {
    reads.update(key, (value) => value + 1, ifAbsent: () => 1);
    if (gates[key] case final gate?) await gate.future;
    if (failNext.remove(key)) throw StateError('One deliberate failed read');
    return rootBundle.load(key);
  }
}

class _AuditBoundaryBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final filename = key.split('/').last;
    final Object data;
    switch (filename) {
      case 'polities.json':
        data = {'A': '政权甲'};
      case 'audit.json':
        data = {
          'identities': {
            'A': {
              'canonicalRanges': [
                [-3, -1],
                [2, 3],
              ],
            },
          },
        };
      case 'index.json':
        data = {
          'records': [
            {'id': 7, 'name': 'A', 'from': -3, 'to': 6},
          ],
        };
      case 'land.geojson':
        data = {'features': <dynamic>[]};
      default:
        data = {
          'features': [
            {
              'id': 7,
              'properties': {
                'Name': 'A',
                'FromYear': -3,
                'ToYear': 6,
                'Area': 100,
              },
              'geometry': {
                'type': 'Polygon',
                'coordinates': [
                  [
                    [100, 20],
                    [104, 20],
                    [104, 24],
                    [100, 24],
                    [100, 20],
                  ],
                ],
              },
            },
          ],
        };
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    return ByteData.sublistView(bytes);
  }
}
