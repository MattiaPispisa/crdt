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

/// A sync of a [ChangeMirror] that holds [size] changes, after the app took
/// in [batch] older changes of a peer back from offline.
class OlderBatchSyncBenchmark extends AsyncFixedCycleTimedBenchmark {
  OlderBatchSyncBenchmark(this.size, this.batch)
    : super(
        'Sync of $batch older remote changes into $size changes',
        // One cycle per fresh setup: a second sync has nothing to take in.
        warmupDuration: Duration.zero,
        measuredCycles: 1,
        batches: 3,
        settleCycles: 0,
      );

  final int size;

  final int batch;

  late CRDTDocument _peer;

  late CRDTDocument _doc;

  late Extension _extension;

  late ChangeMirror _mirror;

  bool _ready = false;

  @override
  Future<void> setup() async {
    if (_ready) await teardown();
    _ready = true;
    resetBridge();
    // Written before the local changes: older than all of them.
    _peer = mapDocument(batch);
    _doc = mapDocument(size);
    _extension = Extension();
    _mirror = ChangeMirror(_extension.client, await _extension.idOf(_doc));
    await _mirror.sync();
    // Out of the timed cycle: the app's import is not the mirror's work.
    _doc.importChanges(_peer.exportChanges());
  }

  @override
  Future<void> run() => _mirror.sync();

  @override
  Future<void> teardown() async {
    _ready = false;
    _extension.dispose();
    _doc.dispose();
    _peer.dispose();
    resetBridge();
  }
}

/// A sync of a [ChangeMirror] that holds [size] changes, after a
/// `garbageCollect` that removes none of them.
class IdlePruneSyncBenchmark extends AsyncFixedCycleTimedBenchmark {
  IdlePruneSyncBenchmark(this.size)
    : super(
        'Sync of $size changes after a prune that removes nothing',
        measuredCycles: 3,
        batches: 3,
        setupPerBatch: false,
      );

  final int size;

  late CRDTDocument _doc;

  late VersionVector _pruned;

  late Extension _extension;

  late ChangeMirror _mirror;

  @override
  Future<void> setup() async {
    resetBridge();
    _doc = mapDocument(1)..takeSnapshot();
    _pruned = _doc.getVersionVector();
    for (var i = 0; i < size; i++) {
      edit(_doc);
    }
    _extension = Extension();
    _mirror = ChangeMirror(_extension.client, await _extension.idOf(_doc));
    await _mirror.sync();
  }

  @override
  Future<void> run() async {
    _doc.garbageCollect(_pruned);
    await _mirror.sync();
  }

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
      for (final load in Load.values) {
        await FirstSyncBenchmark(size, load).report();
      }
      await OlderBatchSyncBenchmark(size, 10000).report();
      await IdlePruneSyncBenchmark(size).report();
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
