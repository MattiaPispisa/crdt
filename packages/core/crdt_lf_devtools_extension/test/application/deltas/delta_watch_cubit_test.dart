// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/deltas/delta_watch_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_time.dart';
import '../../helpers/slow_bridge.dart';

void main() {
  late SlowBridge bridge;
  late CrdtLfClient client;

  setUp(() {
    DevToolsBridge.reset();
    bridge = SlowBridge();
    client = CrdtLfClient(bridge);
  });

  tearDown(() {
    bridge.dispose();
    DevToolsBridge.reset();
  });

  Future<bool> watched(int doc, String handler) async {
    final list = await client.handlers(doc);
    return list.open.firstWhere((h) => h.id == handler).watched;
  }

  testOnFakeTime('a renewal never starts the watch again after a stop', (
    tester,
  ) async {
    final doc = CRDTDocument();
    CRDTTextHandler(doc, 'text').insert(0, 'a');
    final id = (await client.documents()).single.id;
    final cubit = DeltaWatchCubit(
      client,
      id,
      renewEvery: const Duration(milliseconds: 10),
    )..select('text');
    await cubit.setWatching(watching: true);
    bridge.slow = 'watchStop';

    unawaited(cubit.setWatching(watching: false));
    // Past the late answer, and past many renewals.
    await tester.pump(const Duration(seconds: 1));
    expect(cubit.state.watching, isFalse);
    expect(await watched(id, 'text'), isFalse);
    unawaited(cubit.close());
  });

  testOnFakeTime('renews the lease of the watch while watching', (
    tester,
  ) async {
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
    final id = (await client.documents()).single.id;
    final cubit = DeltaWatchCubit(client, id)..select('text');

    await cubit.setWatching(watching: true);
    await tester.pump(DevToolsBridge.lease * 3);
    final before = cubit.state.deltas.length;
    text.insert(0, 'b');
    await tester.pump();
    expect(cubit.state.deltas, hasLength(before + 1));
    expect(await watched(id, 'text'), isTrue);
    unawaited(cubit.close());
  });

  test('a start answered after the selection came back is dropped', () async {
    final doc = CRDTDocument();
    CRDTTextHandler(doc, 'text').insert(0, 'a');
    CRDTTextHandler(doc, 'other').insert(0, 'b');
    final id = (await client.documents()).single.id;
    final cubit = DeltaWatchCubit(client, id)..select('text');
    addTearDown(cubit.close);

    final start = cubit.setWatching(watching: true);
    cubit
      ..select('other')
      ..select('text');
    await start;

    expect(cubit.state.watching, isFalse);
    expect(await watched(id, 'text'), isFalse);
  });

  testOnFakeTime('a lease that ran out marks the deltas as missed', (
    tester,
  ) async {
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
    final id = (await client.documents()).single.id;
    final cubit = DeltaWatchCubit(
      client,
      id,
      renewEvery: DevToolsBridge.lease * 2,
    )..select('text');
    await cubit.setWatching(watching: true);

    await tester.pump(DevToolsBridge.lease);
    // The first delta after the lease: the app stops the watch on it.
    text.insert(1, 'b');
    await tester.pump();
    expect(await watched(id, 'text'), isFalse);
    await tester.pump(DevToolsBridge.lease);
    expect(cubit.state.missed, isTrue);
    expect(await watched(id, 'text'), isTrue);

    await cubit.setWatching(watching: false);
    expect(cubit.state.missed, isTrue);
    await cubit.setWatching(watching: true);
    expect(cubit.state.missed, isFalse);
    unawaited(cubit.close());
  });

  test('watches one handler, newest first, and stops on select', () async {
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
    // A warm cache: the next write gives a delta, not a reset.
    expect(text.value, 'a');
    final other = CRDTTextHandler(doc, 'other')..insert(0, 'x');
    final id = (await client.documents()).single.id;
    final cubit = DeltaWatchCubit(client, id);
    addTearDown(cubit.close);

    await cubit.setWatching(watching: true);
    expect(cubit.state.watching, isFalse, reason: 'no handler selected');

    cubit.select('text');
    await cubit.setWatching(watching: true);
    expect(cubit.state.watching, isTrue);
    await client.watchStart(id, 'other');
    text.insert(1, 'b');
    other.insert(0, 'y');
    await pumpEventQueue();
    final deltas = cubit.state.deltas;
    expect(deltas.map((d) => d.type), ['delta', 'reset']);
    expect(deltas.first.local, isTrue);
    expect(deltas.every((d) => d.handler == 'text'), isTrue);

    cubit.select('other');
    await pumpEventQueue();
    expect(cubit.state.deltas, isEmpty);
    expect(cubit.state.watching, isFalse);
    expect(await watched(id, 'text'), isFalse);
    other.insert(0, 'z');
    await pumpEventQueue();
    expect(cubit.state.deltas, isEmpty);
  });

  test('keeps at most maxDeltas, stops on toggle and on close', () async {
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text');
    final id = (await client.documents()).single.id;
    final cubit = DeltaWatchCubit(client, id)..select('text');
    await cubit.setWatching(watching: true);
    for (var i = 0; i < DeltaWatchCubit.maxDeltas; i++) {
      text.insert(0, 'a');
    }
    await pumpEventQueue();
    expect(cubit.state.deltas, hasLength(DeltaWatchCubit.maxDeltas));
    expect(
      cubit.state.deltas.first.seq,
      greaterThan(cubit.state.deltas.last.seq),
    );

    await cubit.setWatching(watching: false);
    expect(await watched(id, 'text'), isFalse);

    await cubit.setWatching(watching: true);
    await cubit.close();
    await pumpEventQueue();
    expect(await watched(id, 'text'), isFalse);
  });

  test('a refused watch reports the error', () async {
    CRDTDocument();
    final id = (await client.documents()).single.id;
    final cubit = DeltaWatchCubit(client, id)..select('missing');
    addTearDown(cubit.close);
    await cubit.setWatching(watching: true);
    expect(cubit.state.watching, isFalse);
    expect(cubit.state.error, contains('Unknown handler'));
  });
}
