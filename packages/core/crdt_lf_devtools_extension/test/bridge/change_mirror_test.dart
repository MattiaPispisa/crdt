// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hlc_dart/hlc_dart.dart';

import '../helpers/concurrent_peers.dart';

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

  Future<ChangeMirror> mirrorOf(CRDTDocument doc, {int pageSize = 1000}) async {
    final id =
        (await client.documents())
            .firstWhere((d) => d.documentId == doc.documentId)
            .id;
    return ChangeMirror(client, id, pageSize: pageSize);
  }

  List<OperationId> idsOf(ChangeMirror mirror) => [
    for (final entry in mirror.read().entries) entry.change.id,
  ];

  List<OperationId> sortedIds(CRDTDocument doc) => [
    for (final change in doc.exportChanges().sorted()) change.id,
  ];

  test('the first sync loads every page', () async {
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text');
    for (var i = 0; i < 5; i++) {
      text.insert(i, 'a');
    }
    final mirror = await mirrorOf(doc, pageSize: 2);
    final progress = <(int, int)>[];

    await mirror.sync(
      onProgress: (loaded, total) => progress.add((loaded, total)),
    );

    expect(progress, [(2, 5), (4, 5), (5, 5)]);
    expect(idsOf(mirror), sortedIds(doc));
    final entry = mirror.read().entries.first;
    expect(entry.handlerId, 'text');
    expect(entry.handlerType, text.handlerType);
    expect(entry.kind, isNotNull);
    expect(entry.stamped, isFalse);
    expect(entry.byteLength, entry.change.toBytes().length);
  });

  test('a later sync brings only the new changes', () async {
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
    final mirror = await mirrorOf(doc);
    await mirror.sync();
    final first = mirror.read();
    expect(first.from, 0);
    expect(first.entries, hasLength(1));
    text.insert(1, 'b');

    final pages = <int>[];
    await mirror.sync(onProgress: (loaded, _) => pages.add(loaded));

    expect(pages, [2]);
    expect(idsOf(mirror), sortedIds(doc));
    final next = mirror.read(first.mark);
    expect(next.from, 1);
    expect([for (final e in next.entries) e.change.id], [sortedIds(doc).last]);
    expect(mirror.read(next.mark).entries, isEmpty);
  });

  test('a remote change that sorts earlier lands at its place', () async {
    final local = CRDTDocument(
      peerId: PeerId.parse('ffffffff-ffff-4fff-bfff-ffffffffffff'),
    );
    final remote = CRDTDocument(
      peerId: PeerId.parse('00000000-0000-4000-8000-000000000000'),
    );
    CRDTTextHandler(remote, 'remote').insert(0, 'r');
    CRDTTextHandler(local, 'local').insert(0, 'l');
    final mirror = await mirrorOf(local);
    await mirror.sync();
    final mark = mirror.read().mark;

    local.importChanges(remote.exportChanges());
    await mirror.sync();

    expect(idsOf(mirror), sortedIds(local));
    expect(mirror.read().entries.first.change.author, remote.peerId);
    final read = mirror.read(mark);
    expect(read.from, 0);
    expect(read.entries, hasLength(2));
  });

  test('an older remote change keeps the entries before it', () async {
    final (:local, :remote, text: _) = concurrentPeers();
    final mirror = await mirrorOf(local);
    await mirror.sync();
    final mark = mirror.read().mark;

    local.importChanges(remote.exportChanges());
    await mirror.sync();

    final read = mirror.read(mark);
    expect(read.from, 1);
    expect([
      for (final e in read.entries) e.change.id,
    ], sortedIds(local).sublist(1));
    expect(read.entries.first.change.author, remote.peerId);
  });

  test('a page of remote changes interleaves with the entries', () async {
    // Equal clocks on both sides: the remote peer id sorts first, so its
    // changes and the local ones alternate.
    final start = HybridLogicalClock(
      l: DateTime.now().millisecondsSinceEpoch + 3600000,
      c: 0,
    );
    final local = CRDTDocument(
      peerId: PeerId.parse('ffffffff-ffff-4fff-bfff-ffffffffffff'),
      initialClock: start,
    );
    final remote = CRDTDocument(
      peerId: PeerId.parse('00000000-0000-4000-8000-000000000000'),
      initialClock: HybridLogicalClock.fromHlc(start),
    );
    final text = CRDTTextHandler(local, 'text');
    for (var i = 0; i < 3; i++) {
      text.insert(i, 'l');
    }
    final remoteText = CRDTTextHandler(remote, 'other');
    for (var i = 0; i < 2; i++) {
      remoteText.insert(i, 'r');
    }
    final mirror = await mirrorOf(local);
    await mirror.sync();
    final mark = mirror.read().mark;

    local.importChanges(remote.exportChanges());
    await mirror.sync();

    expect(idsOf(mirror), sortedIds(local));
    expect(
      [for (final e in mirror.read().entries) e.change.author],
      [remote.peerId, local.peerId, remote.peerId, local.peerId, local.peerId],
    );
    expect(mirror.read(mark).from, 0);
  });

  test('a prune reloads the mirror', () async {
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
    final mirror = await mirrorOf(doc);
    await mirror.sync();
    final mark = mirror.read().mark;

    doc.takeSnapshot();
    text.insert(1, 'b');
    await mirror.sync();
    expect(mirror.read(mark).from, 0);

    expect(idsOf(mirror), sortedIds(doc));
    expect(mirror.length, 1);
  });
}
