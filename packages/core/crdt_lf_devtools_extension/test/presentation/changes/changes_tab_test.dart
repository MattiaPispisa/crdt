// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/changes/change_log_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/change_detail.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/change_log_list.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/change_row.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/changes_tab.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/lane_graph_painter.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/text_copier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(DevToolsBridge.reset);
  tearDown(DevToolsBridge.reset);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }

  Future<void> openTab(WidgetTester tester, List<String> copied) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
                          : ChangesTab(doc: state.selectedId!),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await settle(tester);
  }

  testWidgets('the detail, a dependency link and the copy', (tester) async {
    final doc = CRDTDocument(documentId: 'd');
    CRDTTextHandler(doc, 'text')
      ..insert(0, 'a')
      ..insert(1, 'b');
    final changes = doc.exportChanges().sorted();
    final copied = <String>[];
    await openTab(tester, copied);

    expect(find.text(ChangeDetail.noSelection), findsOneWidget);
    // Newest first: the second change is the first row.
    final rows = find.text('text');
    expect(rows, findsNWidgets(2));
    await tester.tap(rows.first);
    await settle(tester);

    expect(find.text(ChangeDetail.frontierLabel), findsOneWidget);
    expect(find.textContaining('"b"', findRichText: true), findsOneWidget);
    expect(find.text('→ ${changes.first.id}'), findsOneWidget);

    await tester.tap(find.text('Copy base64'));
    expect(copied, [base64Encode(changes.last.toBytes())]);

    await tester.tap(find.text('→ ${changes.first.id}'));
    await settle(tester);
    expect(find.text(ChangeDetail.frontierLabel), findsNothing);
    expect(find.text('→ ${changes.last.id}'), findsOneWidget);

    final graph = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is LaneGraphPainter,
    );
    expect(graph, findsNWidgets(2));
    // Every change id holds an `@`: the rows stay, the graph goes.
    await tester.enterText(find.byType(TextField), '@');
    await tester.pump();
    expect(find.byType(ChangeRow), findsNWidgets(2));
    expect(graph, findsNothing);

    doc.dispose();
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a closed handler and the snapshot row', (tester) async {
    final remote = CRDTDocument(documentId: 'd');
    CRDTTextHandler(remote, 'closed').insert(0, 'x');
    final doc = CRDTDocument(documentId: 'd');
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
    doc
      ..takeSnapshot()
      ..importChanges(remote.exportChanges());
    remote.dispose();
    // Depends on the remote change: its row merges from the remote lane.
    text.insert(1, 'b');
    await openTab(tester, []);

    expect(find.text(ChangeLogList.snapshotRow), findsOneWidget);
    await tester.tap(find.text('closed'));
    await settle(tester);
    expect(find.text(ChangeDetail.closedNote), findsOneWidget);

    // The keys skip the snapshot row, in both orders.
    String? selected() =>
        tester
            .element(find.byType(ChangeLogList))
            .read<ChangeLogCubit>()
            .state
            .selected
            ?.handlerId;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(selected(), 'closed');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(selected(), 'text');
    await tester.tap(find.text('Newest first'));
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(selected(), 'closed');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(selected(), 'closed');
    await settle(tester);

    expect(find.byType(ChangeRow), findsNWidgets(2));
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.byType(ChangeRow), findsNothing);
    expect(find.text(ChangeLogList.snapshotRow), findsOneWidget);

    doc.dispose();
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
  });
}
