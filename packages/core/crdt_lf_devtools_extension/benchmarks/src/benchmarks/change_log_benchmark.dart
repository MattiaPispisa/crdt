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
/// too, older than the local edit: it lands before the end of the list.
abstract class LiveSyncBenchmark<C extends BlocBase<Object?>>
    extends AsyncFixedCycleTimedBenchmark {
  LiveSyncBenchmark(String what, this.size, {this.concurrent = false})
    : super(
        concurrent
            ? '$what, one edit and an older remote one on $size changes'
            : '$what, one edit on $size changes',
        measuredCycles: 50,
      );

  final int size;

  final bool concurrent;

  late CRDTDocument _doc;

  late CRDTDocument _peer;

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
    _doc = mapDocument(size);
    _peer = CRDTDocument();
    CRDTMapHandler<int>(_peer, 'map', handlerType: 'int map');
    _extension = Extension();
    final id = await _extension.idOf(_doc);
    cubit = create(_extension, id);
    await settle();
  }

  @override
  Future<void> run() async {
    final next = cubit.stream.first;
    if (concurrent) {
      final sent = _peer.getVersionVector();
      edit(_peer);
      edit(_doc);
      _doc.importChanges(_peer.exportChanges(fromVersionVector: sent));
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
    _peer.dispose();
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
