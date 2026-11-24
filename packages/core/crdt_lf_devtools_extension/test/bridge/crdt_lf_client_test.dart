// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
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

  Future<int> trackedId(CRDTDocument doc) async =>
      (await client.documents())
          .firstWhere((d) => d.documentId == doc.documentId)
          .id;

  test('documents and document', () async {
    final peer = PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518');
    final doc = CRDTDocument(peerId: peer, documentId: 'doc');
    final text = CRDTFugueTextHandler(doc, 'text')..insert(0, 'hi');
    CRDTUndoManager(
      doc,
      captureTimeout: Duration.zero,
      stackLimit: 10,
    ).track(text);

    final summary = (await client.documents()).single;
    expect(summary.documentId, 'doc');
    expect(summary.peerId, peer.toString());
    expect(summary.changeCount, 1);
    expect(summary.handlerCount, 1);
    expect(summary.frontiers, [doc.version.single.toString()]);
    expect(summary.versionVector.keys, [peer.toString()]);
    expect(summary.snapshotId, isNull);
    expect(summary.undoManagers, 1);
    expect(summary.recording, isFalse);

    expect(await client.summary(summary.id), summary);
    final detail = await client.document(summary.id);
    expect(detail.summary, summary);
    expect(detail.undo.single.tracked, ['text']);
    expect(detail.undo.single.stackLimit, 10);
    expect(detail.undo.single.captureTimeout, Duration.zero);
    expect(detail.capabilities, isNotEmpty);
  });

  test('handlers and handlerValue', () async {
    final doc = CRDTDocument();
    CRDTTextHandler(doc, 'text').insert(0, 'hi');
    final gone = CRDTMapHandler<int>(doc, 'gone', handlerType: 'map')
      ..set('k', 1);
    doc.deleteHandler(gone);
    final id = await trackedId(doc);

    final handlers = await client.handlers(id);
    final text = handlers.open.single;
    expect(text.id, 'text');
    expect(text.container, isFalse);
    expect(text.children, isEmpty);
    expect(text.changeCount, 1);
    expect(text.deltas, isTrue);
    expect(text.watched, isFalse);
    expect(handlers.deleted, ['gone']);

    final value = (await client.handlerValue(id, 'text', maxString: 1))!;
    expect(value.id, 'text');
    expect(value.type, text.type);
    expect(value.value, {r'$t': 'string', 'length': 2, 'head': 'h'});
    expect((await client.handlers(id)).open.single.cache, HandlerCache.warm);
    expect(
      await client.handlerValue(id, 'text', revision: value.revision),
      isNull,
    );
  });

  test('a handler with changes and no instance is closed', () async {
    final source = CRDTDocument();
    CRDTTextHandler(source, 'text').insert(0, 'a');
    final doc = CRDTDocument()..importChanges(source.exportChanges());

    final closed = (await client.handlers(await trackedId(doc))).closed;
    expect(closed, [
      ClosedHandler(
        id: 'text',
        type: CRDTTextHandler(source, 'x').handlerType,
        changeCount: 1,
      ),
    ]);
  });

  test('changes and operation', () async {
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text');
    for (var i = 0; i < 3; i++) {
      text.insert(i, 'a');
    }
    final id = await trackedId(doc);

    final first = await client.changes(id, limit: 2);
    expect(first.done, isFalse);
    expect(first.changeCount, 3);
    expect(first.pruneEpoch, 0);
    final held = [for (final bytes in first.changes) Change.fromBytes(bytes)];
    final since = VersionVector({});
    for (final change in held) {
      since.update(change.author, change.hlc);
    }
    final rest = await client.changes(id, since: since);
    expect(rest.done, isTrue);
    expect(rest.changes.map(Change.fromBytes), [
      doc.exportChanges().sorted()[2],
    ]);

    final operation = await client.operation(id, first.changes.first);
    expect(operation.changeId, held.first.id.toString());
    expect(operation.handlerId, 'text');
    expect(operation.handlerType, text.handlerType);
    expect(operation.kind, isNotNull);
    expect(operation.stamped, isFalse);
    expect(operation.open, isTrue);
    expect(operation.payload, isA<Map<String, Object?>>());
    expect(operation.error, isNull);
  });

  test('history and snapshot', () async {
    final doc = CRDTDocument();
    final text =
        CRDTTextHandler(doc, 'text')
          ..insert(0, 'a')
          ..insert(1, 'b');
    final id = await trackedId(doc);

    final session = await client.historyOpen(id);
    expect(session.length, 2);
    expect(session.versionVector.keys, [doc.peerId.toString()]);
    expect(session.handlers, [HandlerInfo(id: 'text', type: text.handlerType)]);

    final state = await client.historyState(
      id,
      session: session.session,
      cursor: 1,
      handler: 'text',
    );
    expect(state.cursor, 1);
    expect(state.frontiers, hasLength(1));
    expect(state.value, 'a');
    await client.historyClose(id, session.session);
    await expectLater(
      client.historyState(id, session: session.session, cursor: 0),
      throwsA(isA<HistorySessionClosed>()),
    );
    await expectLater(
      client.historyState(id, session: session.session, cursor: 0),
      throwsA(isA<HistorySessionClosed>()),
    );

    expect((await client.snapshot(id)).snapshot, isNull);
    final taken = doc.takeSnapshot();
    final info = await client.snapshot(id);
    expect(info.snapshot!.id, taken.id);
    expect(info.snapshot!.bytes, taken.toBytes().length);
    expect(info.snapshot!.entries.map((e) => e.key), contains('text'));
    expect(info.deleted, isEmpty);
  });

  test('events: document moves, the event log and the delta watch', () async {
    final received = <CrdtLfEvent>[];
    final subscription = client.events.listen(received.add);
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text');
    await pumpEventQueue();
    final id = await trackedId(doc);
    expect(received.whereType<DocumentsMoved>(), isNotEmpty);

    expect(await client.eventsStart(id), isFalse);
    expect(await client.eventsStart(id), isTrue);
    expect(await client.watchStart(id, 'text'), isFalse);
    expect(await client.watchStart(id, 'text'), isTrue);
    expect((await client.documents()).single.recording, isTrue);
    await pumpEventQueue();
    received.clear();

    // A warm cache: the watch then sends a delta, not a reset.
    expect(text.value, isEmpty);
    text.insert(0, 'a');
    await pumpEventQueue();
    final moved = received.whereType<DocumentMoved>().single;
    expect(moved.doc, id);
    expect(moved.changes, isTrue);
    final logged = received.whereType<DocumentLogEvent>().single;
    expect(logged.type, 'changes');
    expect(logged.source, 'created');
    expect(logged.ids, [doc.exportChanges().single.id.toString()]);
    final delta = received.whereType<HandlerDeltaEvent>().single;
    expect(delta.handler, 'text');
    expect(delta.type, 'delta');
    expect(delta.local, isTrue);

    await client.eventsStop(id);
    await client.watchStop(id, 'text');
    received.clear();
    text.insert(1, 'b');
    await pumpEventQueue();
    expect(received.whereType<DocumentLogEvent>(), isEmpty);
    expect(received.whereType<HandlerDeltaEvent>(), isEmpty);
    await subscription.cancel();
  });

  test('a bad call throws BridgeCallException', () async {
    await expectLater(
      client.document(99),
      throwsA(
        isA<BridgeCallException>().having(
          (e) => e.method,
          'method',
          'document',
        ),
      ),
    );
  });

  test('available and paused are fixed in process', () {
    expect(bridge.available.value, isTrue);
    expect(bridge.paused.value, isFalse);
  });
}
