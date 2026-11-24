// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/failing_bridge.dart';

class _FakeBridge implements CrdtLfBridge {
  final ValueNotifier<bool> connectedValue = ValueNotifier(false);
  final ValueNotifier<bool> availableValue = ValueNotifier(false);
  final ValueNotifier<bool> pausedValue = ValueNotifier(false);
  bool fail = false;

  @override
  Future<Json> call(String method, [Map<String, String>? params]) async {
    if (fail) throw BridgeCallException(method, 'boom');
    return {'protocol': 1, 'documents': <Object?>[]};
  }

  @override
  Stream<BridgeEvent> get events => const Stream.empty();

  @override
  ValueListenable<bool> get connected => connectedValue;

  @override
  ValueListenable<bool> get available => availableValue;

  @override
  ValueListenable<bool> get paused => pausedValue;

  @override
  void dispose() {}
}

void main() {
  setUp(DevToolsBridge.reset);
  tearDown(DevToolsBridge.reset);

  // The reload gate waits 100 ms; a cubit state reaches the tree one frame
  // later.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }

  Future<void> pumpScreen(WidgetTester tester, CrdtLfBridge bridge) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: CrdtLfScreen(bridge: bridge))),
    );
    await settle(tester);
  }

  testWidgets('the empty states and the paused banner', (tester) async {
    final bridge = _FakeBridge();
    await pumpScreen(tester, bridge);
    expect(find.text(CrdtLfScreen.notConnected), findsOneWidget);

    bridge.connectedValue.value = true;
    await settle(tester);
    expect(find.text(CrdtLfScreen.noDocument), findsOneWidget);

    bridge
      ..fail = true
      ..availableValue.value = true
      ..pausedValue.value = true;
    await settle(tester);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text(CrdtLfScreen.paused), findsOneWidget);

    bridge.fail = false;
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(find.text(CrdtLfScreen.noDocument), findsOneWidget);
  });

  testWidgets('a failed reload keeps the tabs and shows the error', (
    tester,
  ) async {
    final doc = CRDTDocument(documentId: 'document-id');
    CRDTTextHandler(doc, 'text').insert(0, 'hi');
    final bridge = FailingBridge();
    await pumpScreen(tester, bridge);
    expect(find.text('State'), findsOneWidget);

    bridge.failing = 'documents';
    final other = CRDTDocument(documentId: 'other');
    await settle(tester);
    expect(find.text('State'), findsOneWidget);
    expect(find.textContaining('The call failed'), findsOneWidget);

    bridge.failing = null;
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(find.textContaining('The call failed'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    doc.dispose();
    other.dispose();
  });

  testWidgets('the header of the selected document', (tester) async {
    final doc = CRDTDocument(documentId: 'document-id');
    CRDTTextHandler(doc, 'text').insert(0, 'hi');

    await pumpScreen(tester, InProcessBridge());
    // The document id is cut at 8 characters.
    expect(find.textContaining(' · document · '), findsOneWidget);
    expect(find.text('1 changes'), findsOneWidget);
    expect(find.text('1 handlers'), findsOneWidget);
    expect(find.text('1 frontiers'), findsOneWidget);
    expect(find.text('snapshot: no'), findsOneWidget);
    expect(find.text('0 undo managers'), findsOneWidget);
    expect(find.text('State'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    doc.dispose();
  });
}
