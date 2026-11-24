// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:bloc/bloc.dart' hide Change;
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/application/changes/change_log_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/time_travel/time_travel_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hlc_dart/hlc_dart.dart';

import '../common/fixture.dart';

final _local = PeerId.parse('ffffffff-ffff-4fff-bfff-ffffffffffff');

final _remote = PeerId.parse('00000000-0000-4000-8000-000000000000');

// One map entry set by another peer.
final _payload = mapDocument(1).exportChanges().single.payloadBytes();

/// One edit of a document of [size] changes, until [cubit] shows it.
///
/// With [concurrent], a change of another peer comes too. It lands one place
/// before the end: it has the clock of the local edit, and its peer id sorts
/// first.
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

  Change? _incoming;

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
    // An hour ahead of the wall clock, so the clock only counts.
    _doc = mapDocument(
      size,
      peerId: _local,
      initialClock: HybridLogicalClock(
        l:
            DateTime.now().millisecondsSinceEpoch +
            const Duration(hours: 1).inMilliseconds,
        c: 0,
      ),
    );
    _extension = Extension();
    final id = await _extension.idOf(_doc);
    cubit = create(_extension, id);
    await settle();
  }

  @override
  void prepareCycle() {
    if (!concurrent) return;
    _incoming = Change.fromPayloadBytes(
      // The clock the local edit of the cycle gets.
      id: OperationId(_remote, _doc.hlc..localEvent(0)),
      deps: _doc.version,
      author: _remote,
      payloadBytes: _payload,
    );
  }

  @override
  Future<void> run() async {
    final next = cubit.stream.first;
    edit(_doc);
    if (_incoming case final change?) _doc.importChanges([change]);
    await next;
  }

  @override
  Future<void> teardown() async {
    _ready = false;
    if (concurrent) _checkOrder();
    await cubit.close();
    _extension.dispose();
    _doc.dispose();
    resetBridge();
  }

  // A remote change that lands at the end would time a plain append.
  void _checkOrder() {
    final tail = _doc.exportChanges().sorted().reversed.take(
      2 * measuredCycles,
    );
    for (final (i, change) in tail.indexed) {
      if (change.author != (i.isEven ? _local : _remote)) {
        throw StateError('The remote change is not one place before the end');
      }
    }
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
