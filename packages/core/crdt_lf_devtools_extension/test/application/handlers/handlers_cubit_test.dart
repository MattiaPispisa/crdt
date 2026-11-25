// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/handlers/handlers_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/settle.dart';

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

  Future<int> trackedId() async => (await client.documents()).single.id;

  test('lists the groups and keeps the selection across reloads', () async {
    final remote = CRDTDocument(documentId: 'd');
    CRDTTextHandler(remote, 'closed').insert(0, 'x');
    final doc = CRDTDocument(documentId: 'd')
      ..importChanges(remote.exportChanges());
    remote.dispose();
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
    final gone = CRDTTextHandler(doc, 'gone')..insert(0, 'b');
    doc.deleteHandler(gone);

    final cubit = HandlersCubit(
      client,
      await trackedId(),
      delay: Duration.zero,
    );
    addTearDown(cubit.close);
    await settle();
    expect(cubit.state.status, LoadStatus.loaded);
    expect(cubit.state.handlers!.open.map((h) => h.id), ['text']);
    expect(cubit.state.handlers!.closed.map((h) => h.id), ['closed']);
    expect(cubit.state.handlers!.deleted, ['gone']);

    cubit.select('text');
    expect(cubit.state.selectedOpen?.revision, 1);
    text.insert(1, 'b');
    await settle();
    expect(cubit.state.selectedOpen?.revision, 2);

    cubit.select('closed');
    expect(cubit.state.selectedOpen, isNull);
    expect(cubit.state.selectedClosed?.changeCount, 1);
    cubit.select('gone');
    expect(cubit.state.selectedDeleted, isTrue);
  });

  test('a failed load keeps the selection and reports the error', () async {
    final cubit = HandlersCubit(client, 42, delay: Duration.zero)
      ..select('text');
    addTearDown(cubit.close);
    await settle();
    expect(cubit.state.status, LoadStatus.failure);
    expect(cubit.state.error, contains('42'));
    expect(cubit.state.selectedId, 'text');
  });
}
