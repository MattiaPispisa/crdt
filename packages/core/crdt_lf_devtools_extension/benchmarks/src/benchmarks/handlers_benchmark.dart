// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter_test/flutter_test.dart';

import '../common/fixture.dart';

/// The `handlers` call the State tab makes again on each change burst, on
/// a document with a closed handler of [size] changes and no snapshot.
class HandlersCallBenchmark extends AsyncTimedBenchmarkBase {
  HandlersCallBenchmark(this.size)
    : super('Repeated handlers call, a closed handler of $size changes');

  final int size;

  late CRDTDocument _doc;

  late Extension _extension;

  late int _id;

  @override
  Future<void> setup() async {
    resetBridge();
    final source = mapDocument(size);
    // The same changes with no handler open: the handler is closed here.
    _doc = CRDTDocument()..importChanges(source.exportChanges());
    source.dispose();
    _extension = Extension();
    _id = await _extension.idOf(_doc);
  }

  @override
  Future<void> run() => _extension.client.handlers(_id);

  @override
  Future<void> teardown() async {
    _extension.dispose();
    _doc.dispose();
    resetBridge();
  }
}

void main() {
  test('handlers', () async {
    for (final size in [10000, 50000]) {
      await HandlersCallBenchmark(size).report();
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
