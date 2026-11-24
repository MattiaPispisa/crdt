// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter_test/flutter_test.dart';

import '../common/fixture.dart';

/// The `snapshot` call the Storage tab makes on each `document` event, on
/// a snapshot of [size] map keys.
class SnapshotCallBenchmark extends AsyncTimedBenchmarkBase {
  SnapshotCallBenchmark(this.size) : super('snapshot call, $size keys');

  final int size;

  late CRDTDocument _doc;

  late Extension _extension;

  late int _id;

  @override
  Future<void> setup() async {
    resetBridge();
    _doc = mapDocument(size)..takeSnapshot();
    _extension = Extension();
    _id = await _extension.idOf(_doc);
  }

  @override
  Future<void> run() => _extension.client.snapshot(_id);

  @override
  Future<void> teardown() async {
    _extension.dispose();
    _doc.dispose();
    resetBridge();
  }
}

void main() {
  test('storage', () async {
    for (final size in [10000, 100000]) {
      await SnapshotCallBenchmark(size).report();
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
