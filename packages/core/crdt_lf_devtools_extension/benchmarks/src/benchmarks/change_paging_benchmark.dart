// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:flutter_test/flutter_test.dart';

import '../common/fixture.dart';

/// A first sync of a [ChangeMirror] over a document of [size] changes, in
/// pages of 1000. With [editing], the app adds a change before each page.
class FirstSyncBenchmark extends AsyncFixedCycleTimedBenchmark {
  FirstSyncBenchmark(this.size, {required this.editing})
    : super(
        'First sync of $size changes, '
        '${editing ? 'one edit per page' : 'idle app'}',
        measuredCycles: 3,
        batches: 3,
        settleCycles: 1,
        setupPerBatch: false,
      );

  final int size;

  final bool editing;

  late CRDTDocument _doc;

  late HookedBridge _bridge;

  late Extension _extension;

  late int _id;

  @override
  Future<void> setup() async {
    resetBridge();
    _doc = mapDocument(size);
    _bridge = HookedBridge('changes', null);
    _extension = Extension(_bridge);
    _id = await _extension.idOf(_doc);
    if (editing) _bridge.before = () => edit(_doc);
  }

  @override
  Future<void> run() => ChangeMirror(_extension.client, _id).sync();

  @override
  Future<void> teardown() async {
    _extension.dispose();
    _doc.dispose();
    resetBridge();
  }
}

void main() {
  test('change paging', () async {
    for (final size in [10000, 50000]) {
      for (final editing in [false, true]) {
        await FirstSyncBenchmark(size, editing: editing).report();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
