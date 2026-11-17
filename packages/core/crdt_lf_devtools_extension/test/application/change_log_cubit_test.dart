// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/changes/change_log_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
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

  // The coalesced event (a microtask), then the gate (a zero timer).
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  Future<ChangeLogCubit> cubitOf(CRDTDocument doc) async {
    final id =
        (await client.documents())
            .firstWhere((d) => d.documentId == doc.documentId)
            .id;
    final cubit = ChangeLogCubit(client, id, delay: Duration.zero);
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

  test('a failed sync reports the error', () async {
    final cubit = ChangeLogCubit(client, 42, delay: Duration.zero);
    addTearDown(cubit.close);
    await settle();
    expect(cubit.state.status, LoadStatus.failure);
    expect(cubit.state.error, contains('42'));
  });
}
