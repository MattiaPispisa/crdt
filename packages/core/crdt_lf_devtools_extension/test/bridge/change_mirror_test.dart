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
    for (final entry in mirror.entries) entry.change.id,
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
    expect(mirror.changeCount, 5);
    final entry = mirror.entries.first;
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
    text.insert(1, 'b');

    final pages = <int>[];
    await mirror.sync(onProgress: (loaded, _) => pages.add(loaded));

    expect(pages, [2]);
    expect(idsOf(mirror), sortedIds(doc));
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

    local.importChanges(remote.exportChanges());
    await mirror.sync();

    expect(idsOf(mirror), sortedIds(local));
    expect(mirror.entries.first.change.author, remote.peerId);
  });

  test('a prune reloads the mirror', () async {
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
    final mirror = await mirrorOf(doc);
    await mirror.sync();
    expect(mirror.pruneEpoch, 0);

    doc.takeSnapshot();
    text.insert(1, 'b');
    await mirror.sync();

    expect(mirror.pruneEpoch, 1);
    expect(idsOf(mirror), sortedIds(doc));
    expect(mirror.length, 1);
  });
}
