// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/application/time_travel/time_travel_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InProcessBridge bridge;
  late CrdtLfClient client;

  setUp(() {
    DevToolsBridge.reset();
    bridge = InProcessBridge();
    client = CrdtLfClient(bridge);
  });

  tearDown(() {
    bridge.dispose();
    DevToolsBridge.reset();
  });

  // The coalesced event (a microtask), then the gates (zero timers).
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  Future<(int, TimeTravelCubit)> open(CRDTDocument doc) async {
    final id =
        (await client.documents())
            .firstWhere((d) => d.documentId == doc.documentId)
            .id;
    final cubit = TimeTravelCubit(
      client,
      id,
      delay: Duration.zero,
      valueDelay: Duration.zero,
    );
    addTearDown(cubit.close);
    await settle();
    return (id, cubit);
  }

  test('opens at the last change and moves the cursor', () async {
    final doc = CRDTDocument(documentId: 'd');
    CRDTTextHandler(doc, 'text')
      ..insert(0, 'a')
      ..insert(1, 'b')
      ..insert(2, 'c');
    final (_, cubit) = await open(doc);

    final replay = [for (final c in doc.exportChanges().sorted()) c.id];
    var state = cubit.state;
    expect(state.status, LoadStatus.loaded);
    expect(state.length, 3);
    expect(state.cursor, 3);
    expect([for (final e in state.frozen) e.change.id], replay);
    expect(state.session!.handlers.map((h) => h.id), ['text']);
    expect(state.value, isNull);

    cubit.select('text');
    await settle();
    expect(cubit.state.value!.value, 'abc');

    cubit.moveTo(1);
    await settle();
    state = cubit.state;
    expect(state.current!.change.id, replay.first);
    expect(state.value!.cursor, 1);
    expect(state.value!.value, 'a');
    expect(state.value!.frontiers, [replay.first.toString()]);

    cubit
      ..previous()
      ..previous();
    await settle();
    expect(cubit.state.cursor, 0);
    expect(cubit.state.current, isNull);
    expect(cubit.state.value!.value, '');

    cubit.moveTo(99);
    expect(cubit.state.cursor, 3);
    cubit.next();
    expect(cubit.state.cursor, 3);
  });

  test('counts the new changes and reopens on them', () async {
    final doc = CRDTDocument(documentId: 'd');
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
    final (_, cubit) = await open(doc);
    cubit.select('text');
    await settle();

    text.insert(1, 'b');
    await settle();
    expect(cubit.state.newChanges, 1);
    expect(cubit.state.length, 1);
    expect(cubit.state.value!.value, 'a');

    await cubit.reopen();
    await settle();
    expect(cubit.state.newChanges, 0);
    expect(cubit.state.length, 2);
    expect(cubit.state.cursor, 2);
    expect(cubit.state.handler, 'text');
    expect(cubit.state.value!.value, 'ab');
  });

  test('closes its session when closed', () async {
    final doc = CRDTDocument(documentId: 'd');
    CRDTTextHandler(doc, 'text').insert(0, 'a');
    final (id, cubit) = await open(doc);
    final session = cubit.state.session!.session;

    await cubit.close();
    expect(
      client.historyState(id, session: session, cursor: 0),
      throwsA(isA<BridgeCallException>()),
    );
  });
}
