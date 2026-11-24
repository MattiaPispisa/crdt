// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/application/time_travel/time_travel_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/concurrent_peers.dart';

// Holds the first [method] call until [release] completes.
class _HeldBridge extends InProcessBridge {
  _HeldBridge(this.method, this.release);

  final String method;

  final Future<void> release;

  /// Whether the held call came.
  bool held = false;

  @override
  Future<Json> call(
    String method, [
    Map<String, String> params = const {},
  ]) async {
    if (method == this.method && !held) {
      held = true;
      await release;
    }
    return super.call(method, params);
  }
}

// Counts the `historyOpen` calls and keeps the closed sessions. Before the
// next open, it runs [beforeOpen]; it holds the next `changes` call until
// [holdChanges] completes, or fails it when [failChanges] is set.
class _ReopenBridge extends InProcessBridge {
  int opens = 0;

  final List<String> closed = [];

  void Function()? beforeOpen;

  Completer<void>? holdChanges;

  bool failChanges = false;

  @override
  Future<Json> call(
    String method, [
    Map<String, String> params = const {},
  ]) async {
    if (method == 'historyOpen') {
      opens++;
      beforeOpen?.call();
      beforeOpen = null;
    }
    if (method == 'historyClose') closed.add(params['session']!);
    if (method == 'changes' && failChanges) {
      failChanges = false;
      throw const BridgeCallException('changes', 'boom');
    }
    if (method == 'changes' && holdChanges != null) {
      final hold = holdChanges!;
      holdChanges = null;
      await hold.future;
    }
    return super.call(method, params);
  }
}

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
      ChangeMirror(client, id),
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

  test('a session the app ended opens again at the cursor', () async {
    final doc = CRDTDocument(documentId: 'd');
    CRDTTextHandler(doc, 'text')
      ..insert(0, 'a')
      ..insert(1, 'b');
    final (id, cubit) = await open(doc);
    cubit.select('text');
    await settle();
    final ended = cubit.state.session!.session;

    await client.historyClose(id, ended);
    // Below the end, where a plain reopen would put the cursor.
    cubit.moveTo(1);
    await settle();
    expect(cubit.state.session!.session, isNot(ended));
    expect(cubit.state.cursor, 1);
    expect(cubit.state.value!.value, 'a');
  });

  test('a renewal that finds the session ended opens a new one', () async {
    final doc = CRDTDocument(documentId: 'd');
    CRDTTextHandler(doc, 'text')
      ..insert(0, 'a')
      ..insert(1, 'b');
    final id = (await client.documents()).single.id;
    final cubit = TimeTravelCubit(
      ChangeMirror(client, id),
      delay: Duration.zero,
      valueDelay: Duration.zero,
      renewEvery: const Duration(milliseconds: 50),
    );
    addTearDown(cubit.close);
    await settle();
    cubit.moveTo(1);
    final ended = cubit.state.session!.session;

    await client.historyClose(id, ended);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(cubit.state.session!.session, isNot(ended));
    expect(cubit.state.cursor, 1);
  });

  test('a resume opens at the cursor the user moved to meanwhile', () async {
    final doc = CRDTDocument(documentId: 'd');
    CRDTTextHandler(doc, 'text')
      ..insert(0, 'a')
      ..insert(1, 'b')
      ..insert(2, 'c');
    final reopening = _ReopenBridge();
    addTearDown(reopening.dispose);
    final reopenClient = CrdtLfClient(reopening);
    final id = (await reopenClient.documents()).single.id;
    final cubit = TimeTravelCubit(
      ChangeMirror(reopenClient, id),
      delay: Duration.zero,
      valueDelay: Duration.zero,
    );
    addTearDown(cubit.close);
    cubit.select('text');
    await settle();

    // The app ends the session; the next value load starts a resume,
    // whose open waits.
    await reopenClient.historyClose(id, cubit.state.session!.session);
    final hold = Completer<void>();
    reopening.holdChanges = hold;
    cubit.moveTo(1);
    await settle();
    cubit.moveTo(2);
    await settle();
    hold.complete();
    await settle();

    expect(reopening.opens, 2);
    expect(cubit.state.cursor, 2);
    expect(cubit.state.value!.value, 'ab');
  });

  test('a reopen that fails after its open closes the new session', () async {
    final doc = CRDTDocument(documentId: 'd');
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
    final reopening = _ReopenBridge();
    addTearDown(reopening.dispose);
    final reopenClient = CrdtLfClient(reopening);
    final id = (await reopenClient.documents()).single.id;
    final cubit = TimeTravelCubit(
      ChangeMirror(reopenClient, id),
      delay: Duration.zero,
      valueDelay: Duration.zero,
    );
    addTearDown(cubit.close);
    await settle();

    // A change between the sync and the open: the second sync fails.
    reopening.beforeOpen = () {
      text.insert(1, 'b');
      reopening.failChanges = true;
    };
    await cubit.reopen();
    await settle();

    expect(reopening.opens, 2);
    expect(reopening.closed, hasLength(1));
    expect(cubit.state.session, isNull);
    expect(cubit.state.status, LoadStatus.failure);
    expect(cubit.state.error, isNot(TimeTravelCubit.taken));
  });

  test('a window that reopens keeps its session from an older one', () async {
    final doc = CRDTDocument(documentId: 'd');
    CRDTTextHandler(doc, 'text').insert(0, 'a');
    final (_, first) = await open(doc);
    final (_, second) = await open(doc);
    await second.reopen();
    await settle();
    final session = second.state.session!.session;

    first.select('text');
    await settle();
    expect(first.state.error, TimeTravelCubit.taken);
    second.select('text');
    await settle();
    expect(second.state.session!.session, session);
    expect(second.state.value!.value, 'a');
  });

  test('a session another window takes is not taken back', () async {
    final doc = CRDTDocument(documentId: 'd');
    CRDTTextHandler(doc, 'text').insert(0, 'a');
    final counting = _ReopenBridge();
    addTearDown(counting.dispose);
    final countingClient = CrdtLfClient(counting);
    final id = (await countingClient.documents()).single.id;
    final cubit = TimeTravelCubit(
      ChangeMirror(countingClient, id),
      delay: Duration.zero,
      valueDelay: Duration.zero,
    );
    addTearDown(cubit.close);
    await settle();

    // The other window opens its own session on the same document.
    await countingClient.historyOpen(id);
    cubit
      ..select('text')
      ..moveTo(0);
    await settle();

    expect(counting.opens, 2);
    expect(cubit.state.session, isNull);
    expect(cubit.state.error, TimeTravelCubit.taken);
  });

  test('a renewal answered after a reopen keeps the new session', () async {
    final doc = CRDTDocument(documentId: 'd');
    CRDTTextHandler(doc, 'text').insert(0, 'a');
    final release = Completer<void>();
    final held = _HeldBridge('historyState', release.future);
    addTearDown(held.dispose);
    final heldClient = CrdtLfClient(held);
    final id = (await heldClient.documents()).single.id;
    final cubit = TimeTravelCubit(
      ChangeMirror(heldClient, id),
      delay: Duration.zero,
      valueDelay: Duration.zero,
      renewEvery: const Duration(milliseconds: 50),
    );
    addTearDown(cubit.close);
    await settle();
    // The first renewal waits; the reopen ends the session it renews.
    while (!held.held) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await cubit.reopen();
    await settle();
    final reopened = cubit.state.session!.session;

    release.complete();
    await settle();
    expect(cubit.state.session!.session, reopened);
  });

  test('a call on the session a reopen replaces resumes nothing', () async {
    final doc = CRDTDocument(documentId: 'd');
    final text =
        CRDTTextHandler(doc, 'text')
          ..insert(0, 'a')
          ..insert(1, 'b')
          ..insert(2, 'c');
    final reopening = _ReopenBridge();
    addTearDown(reopening.dispose);
    final reopenClient = CrdtLfClient(reopening);
    final id = (await reopenClient.documents()).single.id;
    final cubit = TimeTravelCubit(
      ChangeMirror(reopenClient, id),
      delay: Duration.zero,
      valueDelay: Duration.zero,
    );
    addTearDown(cubit.close);
    cubit.select('text');
    await settle();
    cubit.moveTo(1);
    await settle();

    // A change between the sync and the open: the open syncs again, and
    // that sync waits.
    final hold = Completer<void>();
    reopening.beforeOpen = () {
      text.insert(3, 'd');
      reopening.holdChanges = hold;
    };
    final reopen = cubit.reopen();
    await settle();
    // A value load on the replaced session, while the open waits.
    cubit.moveTo(0);
    await settle();
    hold.complete();
    await reopen;
    await settle();

    expect(reopening.opens, 2);
    expect(cubit.state.cursor, 4);
  });

  test('counts an older remote change as new', () async {
    final remote = CRDTDocument(
      peerId: PeerId.parse('00000000-0000-4000-8000-000000000000'),
    );
    CRDTTextHandler(remote, 'remote').insert(0, 'r');
    final doc = CRDTDocument(
      documentId: 'd',
      peerId: PeerId.parse('ffffffff-ffff-4fff-bfff-ffffffffffff'),
    );
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
    final (_, cubit) = await open(doc);

    // Sorts before the session's change, so it lands inside the mirror.
    doc.importChanges(remote.exportChanges());
    await settle();
    expect(cubit.state.newChanges, 1);

    text.insert(1, 'b');
    await settle();
    expect(cubit.state.newChanges, 2);
  });

  test('counts an older remote change in the middle as new', () async {
    final (local: doc, :remote, text: _) = concurrentPeers(documentId: 'd');
    final (_, cubit) = await open(doc);

    doc.importChanges(remote.exportChanges());
    await settle();
    // In the middle, not at the end: the count must not rely on appends.
    expect(doc.exportChanges().sorted()[1].author, remote.peerId);
    expect(cubit.state.newChanges, 1);
  });

  test('a cubit closed during its first sync opens no session', () async {
    final doc = CRDTDocument(documentId: 'd');
    CRDTTextHandler(doc, 'text').insert(0, 'a');
    final release = Completer<void>();
    final held = _HeldBridge('changes', release.future);
    addTearDown(held.dispose);
    final heldClient = CrdtLfClient(held);
    final id = (await heldClient.documents()).single.id;
    final stale = TimeTravelCubit(ChangeMirror(heldClient, id));
    await settle();
    await stale.close();

    final fresh = TimeTravelCubit(
      ChangeMirror(heldClient, id),
      delay: Duration.zero,
      valueDelay: Duration.zero,
    );
    addTearDown(fresh.close);
    await settle();
    release.complete();
    await settle();

    fresh.select('text');
    await settle();
    expect(fresh.state.valueStatus, LoadStatus.loaded);
    expect(fresh.state.value!.value, 'a');
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

  test('renews the lease of its session while open', () async {
    final lease = DevToolsBridge.lease;
    // A wide margin over the renewal period: a slow machine can stall the
    // timers for a while.
    DevToolsBridge.lease = const Duration(seconds: 1);
    addTearDown(() => DevToolsBridge.lease = lease);
    final doc = CRDTDocument(documentId: 'd');
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
    final id = (await client.documents()).single.id;
    final cubit = TimeTravelCubit(
      ChangeMirror(client, id),
      delay: Duration.zero,
      valueDelay: Duration.zero,
      renewEvery: const Duration(milliseconds: 50),
    );
    addTearDown(cubit.close);
    await settle();
    final session = cubit.state.session!.session;

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    // A change ends a session past its lease.
    text.insert(1, 'b');
    expect(cubit.state.session!.session, session);
    final state = await client.historyState(
      id,
      session: cubit.state.session!.session,
      cursor: 1,
    );
    expect(state.cursor, 1);
  });

  test('reports the progress of the first sync', () async {
    final doc = CRDTDocument(documentId: 'd');
    final text = CRDTTextHandler(doc, 'text');
    for (var i = 0; i < 1500; i++) {
      text.insert(0, 'x');
    }
    final id = (await client.documents()).single.id;
    final cubit = TimeTravelCubit(ChangeMirror(client, id));
    addTearDown(cubit.close);
    final progress = <LoadProgress?>[];
    await for (final state in cubit.stream) {
      if (state.session != null) break;
      progress.add(state.progress);
    }
    expect(progress, [
      (loaded: 1000, total: 1500),
      (loaded: 1500, total: 1500),
    ]);
  });
}
