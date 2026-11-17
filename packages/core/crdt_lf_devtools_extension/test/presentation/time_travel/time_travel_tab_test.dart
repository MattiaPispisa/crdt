// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/change_row.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/time_travel/time_travel_tab.dart';
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

  testWidgets('moves the cursor, shows the value and reopens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final doc = CRDTDocument(documentId: 'd');
    final text =
        CRDTTextHandler(doc, 'text')
          ..insert(0, 'a')
          ..insert(1, 'b');
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
              BlocProvider.value(value: documents),
            ],
            child: BlocBuilder<DocumentsCubit, DocumentsState>(
              builder:
                  (context, state) =>
                      state.selectedId == null
                          ? const SizedBox()
                          : TimeTravelTab(doc: state.selectedId!),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await settle(tester);

    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byType(ChangeRow), findsOneWidget);
    expect(find.text(TimeTravelTab.noSelection), findsOneWidget);

    await tester.tap(find.text('text').last);
    await settle(tester);
    expect(find.text('text · at 2'), findsOneWidget);
    expect(find.textContaining('ab', findRichText: true), findsWidgets);

    await tester.tap(find.byTooltip('Previous change'));
    await tester.tap(find.byTooltip('Previous change'));
    await settle(tester);
    expect(find.text('0 / 2'), findsOneWidget);
    expect(find.text(TimeTravelTab.start), findsOneWidget);
    expect(find.text('text · at 0'), findsOneWidget);

    text.insert(2, 'c');
    await settle(tester);
    expect(find.text('1 new changes'), findsOneWidget);
    await tester.tap(find.text('Reopen'));
    await settle(tester);
    expect(find.text('3 / 3'), findsOneWidget);
    expect(find.text('1 new changes'), findsNothing);
    expect(find.text('text · at 3'), findsOneWidget);

    doc.dispose();
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
