// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:flutter_test/flutter_test.dart';

import '../common/fixture.dart';

/// What the app does while the extension pages.
enum Load {
  /// Nothing.
  idle('idle app'),

  /// One edit before each page.
  editing('one edit per page'),

  /// Nothing, and the document starts with one change of another peer.
  quietPeer('a quiet peer');

  const Load(this.label);

  final String label;
}

/// A first sync of a [ChangeMirror] over a document of [size] changes, in
/// pages of 1000, under [load].
class FirstSyncBenchmark extends AsyncFixedCycleTimedBenchmark {
  FirstSyncBenchmark(this.size, this.load)
    : super(
        'First sync of $size changes, ${load.label}',
        measuredCycles: 3,
        batches: 3,
        settleCycles: 1,
      );

  final int size;

  final Load load;

  late CRDTDocument _doc;

  late HookedBridge _bridge;

  late Extension _extension;

  late int _id;

  bool _ready = false;

  @override
  Future<void> setup() async {
    // Again before each batch: with edits, each sync grows the document.
    if (_ready) await teardown();
    _ready = true;
    resetBridge();
    _doc = mapDocument(size, quietPeer: load == Load.quietPeer);
    _bridge = HookedBridge('changes', null);
    _extension = Extension(_bridge);
    _id = await _extension.idOf(_doc);
    if (load == Load.editing) _bridge.before = () => edit(_doc);
  }

  @override
  Future<void> run() => ChangeMirror(_extension.client, _id).sync();

  @override
  Future<void> teardown() async {
    _ready = false;
    _extension.dispose();
    _doc.dispose();
    resetBridge();
  }
}

void main() {
  test('change paging', () async {
    for (final size in [10000, 50000]) {
      for (final load in Load.values) {
        await FirstSyncBenchmark(size, load).report();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
