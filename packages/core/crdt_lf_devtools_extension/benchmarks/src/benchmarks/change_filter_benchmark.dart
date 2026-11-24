// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/application/changes/change_log_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:flutter_test/flutter_test.dart';

import '../common/fixture.dart';

/// A new text in the id filter of the Changes tab, over [size] changes:
/// a key typed in the filter field.
class IdFilterBenchmark extends AsyncFixedCycleTimedBenchmark {
  IdFilterBenchmark(this.size)
    : super('Id filter on $size changes', measuredCycles: 20);

  final int size;

  late CRDTDocument _doc;

  late Extension _extension;

  late ChangeLogCubit _cubit;

  var _typed = 0;

  bool _ready = false;

  @override
  Future<void> setup() async {
    // A cycle changes only the filter: one document serves every batch.
    if (_ready) return;
    _ready = true;
    resetBridge();
    _doc = mapDocument(size);
    _extension = Extension();
    final id = await _extension.idOf(_doc);
    _cubit = ChangeLogCubit(
      ChangeMirror(_extension.client, id),
      delay: Duration.zero,
    );
    await settle();
  }

  @override
  Future<void> run() async {
    _cubit.setFilter(ChangeFilter(text: '${_typed++ % 10}'));
  }

  @override
  Future<void> teardown() async {
    _ready = false;
    await _cubit.close();
    _extension.dispose();
    _doc.dispose();
    resetBridge();
  }
}

void main() {
  test('change filter', () async {
    for (final size in [10000, 50000]) {
      await IdFilterBenchmark(size).report();
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
