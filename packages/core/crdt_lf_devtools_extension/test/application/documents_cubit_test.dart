// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InProcessBridge bridge;
  late DocumentsCubit cubit;

  setUp(() {
    DevToolsBridge.reset();
    bridge = InProcessBridge();
    cubit = DocumentsCubit(CrdtLfClient(bridge), delay: Duration.zero);
  });

  tearDown(() async {
    await cubit.close();
    bridge.dispose();
    DevToolsBridge.reset();
  });

  // The coalesced event (a microtask), then the gate (a zero timer).
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  List<String> documentIds() => [
    for (final d in cubit.state.documents) d.documentId,
  ];

  test('a new document appears and a disposed one leaves', () async {
    await settle();
    expect(cubit.state.status, DocumentsStatus.loaded);
    expect(cubit.state.documents, isEmpty);
    expect(cubit.state.selectedId, isNull);

    final doc = CRDTDocument(documentId: 'a');
    await settle();
    expect(documentIds(), ['a']);
    expect(cubit.state.selected?.documentId, 'a');

    doc.dispose();
    await settle();
    expect(documentIds(), isEmpty);
    expect(cubit.state.selectedId, isNull);
  });

  test('a change reloads, and the selection survives it', () async {
    CRDTDocument(documentId: 'a');
    final b = CRDTDocument(documentId: 'b');
    await settle();
    final id = cubit.state.documents.last.id;
    cubit.select(id);

    CRDTTextHandler(b, 'text').insert(0, 'x');
    await settle();
    expect(cubit.state.selectedId, id);
    expect(cubit.state.selected?.changeCount, 1);

    cubit.select(-1);
    expect(cubit.state.selectedId, id);
  });
}
