// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'traces/scenarios.dart';

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
      expect(
        json,
        file.readAsStringSync(),
        reason:
            'update it: fvm flutter test --update-goldens '
            'test/traces_test.dart',
      );
    });
  }
}
