// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

@TestOn('vm')
library;

import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter_test/flutter_test.dart';

import 'traces/scenarios.dart';
import 'traces/trace.dart';

const _update = 'fvm flutter test --update-goldens test/traces_test.dart';

void main() {
  for (final MapEntry(key: id, value: record) in scenarios.entries) {
    test('the "$id" trace matches traces/$id.json', () async {
      final trace = await record();
      addTearDown(trace.dispose);
      final file = File('traces/$id.json');
      final json = trace.encode();
      if (autoUpdateGoldenFiles) {
        file
          ..createSync(recursive: true)
          ..writeAsStringSync(json);
        return;
      }
      if (!file.existsSync()) {
        fail('no traces/$id.json: $_update');
      }
      expect(json, file.readAsStringSync(), reason: 'update it: $_update');
    });
  }

  test('a sync fails when the peers read different values', () {
    final trace = Trace(
      kind: 'text',
      peers: {'Alice': CRDTDocument(), 'Bob': CRDTDocument()},
      read: (peer) => [(text: peer, author: null)],
    );
    addTearDown(trace.dispose);

    expect(() => trace.sync('They sync.'), throwsA(isA<TestFailure>()));
  });

  test('every file in traces/ has a scenario', () {
    final stale =
        Directory('traces').listSync().whereType<File>().where((file) {
          final name = file.uri.pathSegments.last;
          return name.endsWith('.json') &&
              !scenarios.containsKey(name.replaceFirst('.json', ''));
        }).toList();
    if (autoUpdateGoldenFiles) {
      for (final file in stale) {
        file.deleteSync();
      }
      return;
    }
    expect(
      stale.map((file) => file.path),
      isEmpty,
      reason: 'delete them: $_update',
    );
  });
}
