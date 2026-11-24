// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/storage/storage_tab.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/handler_names.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/text_copier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(DevToolsBridge.reset);
  tearDown(DevToolsBridge.reset);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }

  testWidgets('shows the storage before and after a snapshot', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final remote = CRDTDocument(documentId: 'd');
    CRDTListHandler<int>(remote, 'list', handlerType: 'app/ints').insert(0, 1);
    final doc = CRDTDocument(documentId: 'd')
      ..importChanges(remote.exportChanges());
    remote.dispose();
    CRDTTextHandler(doc, 'text').insert(0, 'a');
    final gone = CRDTTextHandler(doc, 'gone')..insert(0, 'b');
    doc.deleteHandler(gone);
    CRDTUndoManager(doc).track(CRDTFugueTextHandler(doc, 'undo'));
    const names = {
      'text': 'title',
      'gone': 'old title',
      'list': 'numbers',
      'undo': 'body',
    };
    final copied = <String>[];
    final bridge = InProcessBridge();
    addTearDown(bridge.dispose);
    final client = CrdtLfClient(bridge);
    final documents = DocumentsCubit(client);
    addTearDown(documents.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              RepositoryProvider.value(value: client),
              RepositoryProvider.value(value: TextCopier(copied.add)),
              BlocProvider.value(value: documents),
            ],
            child: BlocBuilder<DocumentsCubit, DocumentsState>(
              builder:
                  (context, state) =>
                      state.selectedId == null
                          ? const SizedBox()
                          : HandlerNames(
                            names: names,
                            child: StorageTab(doc: state.selectedId!),
                          ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await settle(tester);

    expect(find.text(StorageTab.noSnapshot), findsOneWidget);
    expect(find.text('Deleted handlers'), findsOneWidget);
    expect(find.text('old title'), findsOneWidget);
    expect(find.text('me'), findsOneWidget);
    expect(find.textContaining('tracked [body]'), findsOneWidget);
    expect(find.text(StorageTab.missingLabel), findsNothing);

    final snapshot = doc.takeSnapshot();
    await settle(tester);
    expect(find.text(StorageTab.noSnapshot), findsNothing);
    expect(find.text('reserved'), findsWidgets);
    expect(find.text('me'), findsNWidgets(2));
    expect(find.text(StorageTab.missingLabel), findsOneWidget);
    await tester.tap(find.byTooltip('Copy the snapshot id'));
    expect(copied, [snapshot.id]);

    doc.dispose();
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
