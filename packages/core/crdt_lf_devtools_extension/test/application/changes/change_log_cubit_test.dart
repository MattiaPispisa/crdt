// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/changes/change_log_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/concurrent_peers.dart';

// Counts the changes the app sends.
class _CountingBridge extends InProcessBridge {
  int changes = 0;

  @override
  Future<Json> call(String method, [Map<String, String> params = const {}]) {
    return super.call(method, params).then((json) {
      if (method == 'changes') changes += (json['changes']! as List).length;
      return json;
    });
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

  // The coalesced event (a microtask), then the gate (a zero timer).
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  Future<ChangeLogCubit> cubitOf(CRDTDocument doc) async {
    final id =
        (await client.documents())
            .firstWhere((d) => d.documentId == doc.documentId)
            .id;
    final cubit = ChangeLogCubit(
      ChangeMirror(client, id),
      delay: Duration.zero,
    );
    addTearDown(cubit.close);
    await settle();
    return cubit;
  }

  List<OperationId> visibleIds(ChangeLogCubit cubit) => [
    for (final entry in cubit.state.visible) entry.change.id,
  ];

  test('filters by author, handler, kind and id', () async {
    final remote = CRDTDocument(documentId: 'd');
    CRDTTextHandler(remote, 'b').insert(0, 'r');
    final doc = CRDTDocument(documentId: 'd')
      ..importChanges(remote.exportChanges());
    remote.dispose();
    final a =
        CRDTTextHandler(doc, 'a')
          ..insert(0, 'xy')
          ..delete(0, 1);
    final cubit = await cubitOf(doc);

    final replay = [for (final c in doc.exportChanges().sorted()) c.id];
    expect(cubit.state.status, LoadStatus.loaded);
    expect(visibleIds(cubit), replay.reversed);
    expect(cubit.state.index.authors, hasLength(2));
    expect(cubit.state.index.handlers, ['a', 'b']);
    expect(cubit.state.index.kinds, [0, 1]);

    cubit.setNewestFirst(newestFirst: false);
    expect(visibleIds(cubit), replay);

    cubit.setFilter(ChangeFilter(author: doc.peerId.toString()));
    expect(cubit.state.visible.map((e) => e.handlerId), ['a', 'a']);

    cubit.setFilter(const ChangeFilter(handler: 'b'));
    expect(cubit.state.visible.single.change.author, isNot(doc.peerId));

    cubit.setFilter(const ChangeFilter(handler: 'a', kind: 1));
    expect(cubit.state.visible.single.kind, 1);

    final last = replay.last.toString();
    cubit.setFilter(ChangeFilter(text: last.substring(last.indexOf('@'))));
    expect(visibleIds(cubit), [replay.last]);
    expect(a.value, 'y');
  });

  test('keeps the selection across a sync and loads its operation', () async {
    final doc = CRDTDocument(documentId: 'd');
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
    final cubit = await cubitOf(doc);
    final first = cubit.state.index.entries.single.change.id;

    cubit.select(first);
    expect(cubit.state.operationStatus, LoadStatus.initial);
    await settle();
    expect(cubit.state.operationStatus, LoadStatus.loaded);
    expect(cubit.state.operation?.open, isTrue);
    expect('${cubit.state.operation?.payload}', contains('[text, a]'));
    expect(cubit.state.index.dependentsOf(first), isEmpty);

    text.insert(1, 'b');
    await settle();
    expect(cubit.state.index.entries, hasLength(2));
    expect(cubit.state.selectedId, first);
    expect(cubit.state.operation?.open, isTrue);
    final second = cubit.state.index.entries.last.change.id;
    expect(cubit.state.index.dependentsOf(first), [second]);

    cubit.select(second);
    await settle();
    expect('${cubit.state.operation?.payload}', contains('[text, b]'));
  });

  test('an append leaves the index and the list of the state before', () async {
    final doc = CRDTDocument(documentId: 'd');
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
    final cubit = await cubitOf(doc);
    cubit.setFilter(const ChangeFilter(handler: 'text'));
    final before = cubit.state;
    final first = before.index.entries.single.change.id;

    text.insert(1, 'b');
    CRDTTextHandler(doc, 'other').insert(0, 'c');
    await settle();

    final replay = [for (final c in doc.exportChanges().sorted()) c.id];
    expect(cubit.state.index.entries, hasLength(3));
    expect(visibleIds(cubit), replay.sublist(0, 2).reversed);
    expect(before.index.entries, hasLength(1));
    expect(before.index.entryOf(replay[1]), isNull);
    expect(before.index.dependentsOf(first), isEmpty);
    expect(before.index.graph.rows, hasLength(1));
    expect(before.visible.map((e) => e.change.id), [first]);
  });

  test('an older remote change lands at its place in the list', () async {
    final remote = CRDTDocument(
      peerId: PeerId.parse('00000000-0000-4000-8000-000000000000'),
    );
    CRDTTextHandler(remote, 'text').insert(0, 'r');
    final doc = CRDTDocument(
      documentId: 'd',
      peerId: PeerId.parse('ffffffff-ffff-4fff-bfff-ffffffffffff'),
    );
    CRDTTextHandler(doc, 'text').insert(0, 'a');
    final cubit = await cubitOf(doc);
    cubit.setFilter(const ChangeFilter(handler: 'text'));

    doc.importChanges(remote.exportChanges());
    await settle();

    final replay = [for (final c in doc.exportChanges().sorted()) c.id];
    expect(replay.first.peerId, remote.peerId);
    expect([for (final e in cubit.state.index.entries) e.change.id], replay);
    expect(visibleIds(cubit), replay.reversed);
    expect(cubit.state.index.authors, hasLength(2));
  });

  test('an index with its last entries replaced is the index of them', () {
    final remote = CRDTDocument(peerId: PeerId.generate());
    CRDTTextHandler(remote, 'other').insert(0, 'r');
    final doc = CRDTDocument(peerId: PeerId.generate());
    final text = CRDTTextHandler(doc, 'text');
    for (var i = 0; i < 4; i++) {
      text.insert(i, 'x');
    }
    final entriesOf = [
      for (final change in doc.exportChanges().sorted())
        MirrorEntry.decode(change.toBytes()),
    ];
    final remoteEntry = MirrorEntry.decode(
      remote.exportChanges().single.toBytes(),
    );
    // The tail goes away with the author and the handler it brought.
    final index = ChangeIndex([...entriesOf.take(2), remoteEntry]);
    final added = entriesOf.sublist(2);

    final replaced = index.replaceFrom(2, added);
    final fresh = ChangeIndex(entriesOf);

    expect(replaced.entries, fresh.entries);
    expect(replaced.authors, fresh.authors);
    expect(replaced.handlers, fresh.handlers);
    expect(replaced.kinds, fresh.kinds);
    expect(replaced.entryOf(remoteEntry.change.id), isNull);
    for (final entry in entriesOf) {
      expect(
        replaced.dependentsOf(entry.change.id),
        fresh.dependentsOf(entry.change.id),
      );
    }
    expect(replaced.graph.rows, fresh.graph.rows);
  });

  test('an older remote change in the middle keeps the filter', () async {
    final (:local, :remote, :text) = concurrentPeers(documentId: 'd');
    final cubit = await cubitOf(local);
    cubit.setFilter(const ChangeFilter(handler: 'text'));

    local.importChanges(remote.exportChanges());
    text.insert(3, 'c');
    await settle();

    final replay = [for (final c in local.exportChanges().sorted()) c.id];
    expect(replay[1].peerId, remote.peerId);
    expect([for (final e in cubit.state.index.entries) e.change.id], replay);
    expect(visibleIds(cubit), replay.reversed);
    expect(cubit.state.index.graph.rows, hasLength(4));
    expect(cubit.state.index.authors, hasLength(2));
  });

  test('a filter set again after a sync in the middle sees it', () async {
    final (:local, :remote, text: _) = concurrentPeers(documentId: 'd');
    final cubit = await cubitOf(local);
    cubit
      ..setFilter(const ChangeFilter(handler: 'text'))
      ..setFilter(const ChangeFilter());

    local.importChanges(remote.exportChanges());
    await settle();
    cubit.setFilter(const ChangeFilter(handler: 'text'));

    final replay = [for (final c in local.exportChanges().sorted()) c.id];
    expect(visibleIds(cubit), replay.reversed);
  });

  test('a selection that a sync brings in the middle loads', () async {
    final (:local, :remote, text: _) = concurrentPeers(documentId: 'd');
    final cubit = await cubitOf(local);
    final arriving = remote.exportChanges().single.id;
    cubit.select(arriving);
    await settle();
    expect(cubit.state.selected, isNull);

    local.importChanges(remote.exportChanges());
    await settle();

    expect(cubit.state.selected?.change.id, arriving);
    expect(cubit.state.operationStatus, LoadStatus.loaded);
  });

  test('an index extended twice from one base keeps both lines', () {
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text');
    for (var i = 0; i < 3; i++) {
      text.insert(i, 'x');
    }
    final [a, b, c] = [
      for (final change in doc.exportChanges().sorted())
        MirrorEntry.decode(change.toBytes()),
    ];
    final base = ChangeIndex([a]);

    final first = base.extend([b]);
    final second = base.extend([c]);

    expect(first.entries, [a, b]);
    expect(second.entries, [a, c]);
    expect(second.entryOf(b.change.id), isNull);
    expect(second.dependentsOf(a.change.id), [
      if (c.deps.contains(a.change.id)) c.change.id,
    ]);
  });

  test('a second cubit on the same mirror loads no change again', () async {
    final counting = _CountingBridge();
    addTearDown(counting.dispose);
    final client = CrdtLfClient(counting);
    final doc = CRDTDocument(documentId: 'd');
    final text = CRDTTextHandler(doc, 'text');
    for (var i = 0; i < 1500; i++) {
      text.insert(0, 'x');
    }
    final mirror = ChangeMirror(client, (await client.documents()).single.id);
    final first = ChangeLogCubit(mirror, delay: Duration.zero);
    await settle();
    await first.close();
    expect(counting.changes, 1500);

    final second = ChangeLogCubit(mirror, delay: Duration.zero);
    addTearDown(second.close);
    await settle();

    expect(second.state.index.entries, hasLength(1500));
    expect(counting.changes, 1500);
  });

  test('a starting selection gets its operation after a sync', () async {
    final doc = CRDTDocument(documentId: 'd');
    CRDTTextHandler(doc, 'text').insert(0, 'a');
    final id = (await client.documents()).single.id;
    final cubit = ChangeLogCubit(
      ChangeMirror(client, id),
      selected: doc.version.single,
      delay: Duration.zero,
    );
    addTearDown(cubit.close);
    await settle();
    expect(cubit.state.selected?.change.id, doc.version.single);
    expect(cubit.state.operationStatus, LoadStatus.loaded);
  });

  test('a prune reloads the list and drops a pruned selection', () async {
    final doc = CRDTDocument(documentId: 'd');
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
    final cubit = await cubitOf(doc);
    cubit.select(cubit.state.index.entries.single.change.id);
    await settle();

    doc.takeSnapshot();
    text.insert(1, 'b');
    await settle();

    expect(cubit.state.index.entries, hasLength(1));
    expect(
      cubit.state.index.entries.single.change.id,
      doc.exportChanges().single.id,
    );
    expect(cubit.state.selectedId, isNull);
    expect(cubit.state.operation, isNull);
  });

  test('a prune that shrinks the list keeps a filter working', () async {
    final doc = CRDTDocument(documentId: 'd');
    final text = CRDTTextHandler(doc, 'text');
    for (var i = 0; i < 3; i++) {
      text.insert(i, 'x');
    }
    final cubit = await cubitOf(doc);
    cubit.setFilter(const ChangeFilter(handler: 'text'));

    doc.takeSnapshot();
    text.insert(0, 'y');
    await settle();
    expect(cubit.state.status, LoadStatus.loaded);
    expect(visibleIds(cubit), [doc.exportChanges().single.id]);

    text.insert(0, 'z');
    await settle();
    expect(cubit.state.status, LoadStatus.loaded);
    expect(cubit.state.visible, hasLength(2));
  });

  test('a failed sync reports the error', () async {
    final cubit = ChangeLogCubit(
      ChangeMirror(client, 42),
      delay: Duration.zero,
    );
    addTearDown(cubit.close);
    await settle();
    expect(cubit.state.status, LoadStatus.failure);
    expect(cubit.state.error, contains('42'));
  });

  test('reports the progress of the first sync', () async {
    final doc = CRDTDocument(documentId: 'd');
    final text = CRDTTextHandler(doc, 'text');
    for (var i = 0; i < 1500; i++) {
      text.insert(0, 'x');
    }
    final id = (await client.documents()).single.id;
    final cubit = ChangeLogCubit(
      ChangeMirror(client, id),
      delay: Duration.zero,
    );
    addTearDown(cubit.close);
    final progress = <LoadProgress?>[];
    await for (final state in cubit.stream) {
      if (state.status == LoadStatus.loaded) break;
      progress.add(state.progress);
    }
    expect(progress, [
      (loaded: 1000, total: 1500),
      (loaded: 1500, total: 1500),
    ]);
  });
}
