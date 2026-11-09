// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

@TestOn('browser')
library;

import 'dart:io';

import 'package:crdt_lf_drift/crdt_lf_drift.dart';
import 'package:test/test.dart';

void main() {
  final pointsToFromDatabase = isA<UnsupportedError>().having(
    (error) => error.message,
    'message',
    allOf(contains('CRDTDrift.fromDatabase'), contains('WasmDatabase')),
  );

  test('open and memory throw on the web, naming the way that works', () {
    expect(() => CRDTDrift.open(File('app.db')), throwsA(pointsToFromDatabase));
    expect(CRDTDrift.memory, throwsA(pointsToFromDatabase));
  });
}
