// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/handlers/handlers_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/screen.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/state/handler_detail.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/state/handler_tree.dart';
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

  Finder rich(String text) => find.textContaining(text, findRichText: true);

  testWidgets('the tree, the detail, a ref tap and the copy', (tester) async {
    final doc = CRDTDocument(documentId: 'd');
    final child = CRDTTextHandler(doc, 'child')..insert(0, 'nested');
    CRDTMapRefHandler(doc, 'root').setRef('slot', child);
    final gone = CRDTTextHandler(doc, 'gone')..insert(0, 'x');
    doc.deleteHandler(gone);
    final copied = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CrdtLfScreen(
            bridge: InProcessBridge(),
            copier: TextCopier(copied.add),
          ),
        ),
      ),
    );
    await settle(tester);
    await settle(tester);
    expect(find.text('Open (2)'), findsOneWidget);
    expect(find.text(HandlerDetail.noSelection), findsOneWidget);

    // The child is drawn under its container, not as a root.
    final rootTop = tester.getTopLeft(find.text('root')).dy;
    final childTop = tester.getTopLeft(find.text('child')).dy;
    expect(childTop, greaterThan(rootTop));

    await tester.tap(find.text('root'));
    await settle(tester);
    expect(find.text(HandlerDetail.cacheNote), findsOneWidget);
    expect(find.text('CRDTMapRefHandler'), findsWidgets);

    await tester.tap(find.text('→ child'));
    await settle(tester);
    expect(rich('"nested"'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy'));
    expect(copied, ['"nested"']);

    // Down skips the group rows: from the last open handler it stays.
    String? selected() =>
        tester
            .element(find.byType(HandlerTree))
            .read<HandlersCubit>()
            .state
            .selectedId;
    await tester.tap(find.text('root'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(selected(), 'child');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(selected(), 'child');
    await settle(tester);

    await tester.tap(find.text('Deleted (1)'));
    await tester.pump();
    await tester.tap(find.text('gone').first);
    await settle(tester);
    expect(find.text(HandlerDetail.deletedNote), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text(HandlerTree.noMatch), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    doc.dispose();
  });

  testWidgets('the delta watch of the selected handler', (tester) async {
    final doc = CRDTDocument(documentId: 'd');
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CrdtLfScreen(bridge: InProcessBridge())),
      ),
    );
    await settle(tester);
    await settle(tester);
    await tester.tap(find.text('text'));
    await settle(tester);
    expect(find.text(HandlerDetail.watchNote), findsOneWidget);

    await tester.tap(find.text('Watch deltas'));
    await settle(tester);
    expect(find.text('initial'), findsOneWidget);

    text.insert(1, 'b');
    await settle(tester);
    expect(find.text('local'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    expect(text.hasDeltaListeners, isFalse);
    doc.dispose();
  });

  testWidgets('a document with no handler', (tester) async {
    final doc = CRDTDocument(documentId: 'd');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CrdtLfScreen(bridge: InProcessBridge())),
      ),
    );
    await settle(tester);
    await settle(tester);
    expect(find.text(HandlerTree.empty), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    doc.dispose();
  });
}
