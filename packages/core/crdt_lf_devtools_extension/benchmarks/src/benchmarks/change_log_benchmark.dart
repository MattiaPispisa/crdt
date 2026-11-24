// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:bloc/bloc.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/application/changes/change_log_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/time_travel/time_travel_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:flutter_test/flutter_test.dart';

import '../common/fixture.dart';

/// One edit of a document of [size] changes, until [cubit] shows it.
///
/// With [concurrent], a peer that edits at the same time sends one change
/// too. It lands one place before the end: it sorts after what the peer
/// got, and before the local edit.
abstract class LiveSyncBenchmark<C extends BlocBase<Object?>>
    extends AsyncFixedCycleTimedBenchmark {
  LiveSyncBenchmark(String what, this.size, {this.concurrent = false})
    : super(
        concurrent
            ? '$what, one edit and a concurrent remote one on $size changes'
            : '$what, one edit on $size changes',
        measuredCycles: 50,
      );

  final int size;

  final bool concurrent;

  late CRDTDocument _doc;

  CRDTDocument? _peer;

  late Extension _extension;

  late C cubit;

  bool _ready = false;

  C create(Extension extension, int id);

  @override
  Future<void> setup() async {
    // Again before each batch: the warm-up and each batch grow the document.
    if (_ready) await teardown();
    _ready = true;
    resetBridge();
    // The peer id sorts first: a remote change equal in clock to the local
    // edit goes before it.
    _doc = mapDocument(
      size,
      peerId: PeerId.parse('ffffffff-ffff-4fff-bfff-ffffffffffff'),
    );
    if (concurrent) {
      final peer =
          _peer = CRDTDocument(
            peerId: PeerId.parse('00000000-0000-4000-8000-000000000000'),
          )..importChanges(_doc.exportChanges());
      CRDTMapHandler<int>(peer, 'map', handlerType: 'int map');
    }
    _extension = Extension();
    final id = await _extension.idOf(_doc);
    cubit = create(_extension, id);
    await settle();
  }

  @override
  Future<void> run() async {
    final next = cubit.stream.first;
    if (_peer case final peer?) {
      peer.importChanges(
        _doc.exportChanges(fromVersionVector: peer.getVersionVector()),
      );
      final sent = peer.getVersionVector();
      edit(peer);
      edit(_doc);
      _doc.importChanges(peer.exportChanges(fromVersionVector: sent));
    } else {
      edit(_doc);
    }
    await next;
  }

  @override
  Future<void> teardown() async {
    _ready = false;
    await cubit.close();
    _extension.dispose();
    _doc.dispose();
    _peer?.dispose();
    _peer = null;
    resetBridge();
  }
}

class ChangeLogSyncBenchmark extends LiveSyncBenchmark<ChangeLogCubit> {
  ChangeLogSyncBenchmark(int size, {super.concurrent})
    : super('Change log', size);

  @override
  ChangeLogCubit create(Extension extension, int id) =>
      ChangeLogCubit(ChangeMirror(extension.client, id), delay: Duration.zero);
}

class TimeTravelSyncBenchmark extends LiveSyncBenchmark<TimeTravelCubit> {
  TimeTravelSyncBenchmark(int size, {super.concurrent})
    : super('Time travel', size);

  @override
  TimeTravelCubit create(Extension extension, int id) => TimeTravelCubit(
    ChangeMirror(extension.client, id),
    delay: Duration.zero,
    valueDelay: Duration.zero,
  );
}

void main() {
  test('change log', () async {
    for (final size in [10000, 50000]) {
      for (final concurrent in [false, true]) {
        await ChangeLogSyncBenchmark(size, concurrent: concurrent).report();
        await TimeTravelSyncBenchmark(size, concurrent: concurrent).report();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
