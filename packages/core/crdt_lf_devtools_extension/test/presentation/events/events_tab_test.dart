// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/events/event_log_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/change_detail.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/changes_tab.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/events/events_tab.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/change_link.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/text_copier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _MissedCubit extends EventLogCubit {
  _MissedCubit(super.client, super.doc);

  void miss() => emit(const EventLogState(recording: true, missed: true));
}

void main() {
  setUp(DevToolsBridge.reset);
  tearDown(DevToolsBridge.reset);

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }

  testWidgets('the missed note clears with no event in the list', (
    tester,
  ) async {
    final bridge = InProcessBridge();
    addTearDown(bridge.dispose);
    final events = _MissedCubit(CrdtLfClient(bridge), 0)..miss();
    addTearDown(events.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<EventLogCubit>.value(
            value: events,
            child: EventsTab(onChange: (_) {}),
          ),
        ),
      ),
    );
    expect(find.text(EventsTab.missedNote), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await settle(tester);
    expect(find.text(EventsTab.missedNote), findsNothing);
  });

  testWidgets('record, a row, its detail and a link to the change', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final doc = CRDTDocument(documentId: 'd');
    final text = CRDTTextHandler(doc, 'text');
    final bridge = InProcessBridge();
    addTearDown(bridge.dispose);
    final client = CrdtLfClient(bridge);
    final documents = DocumentsCubit(client);
    addTearDown(documents.close);
    final id = (await client.documents()).single.id;
    final events = EventLogCubit(client, id);
    addTearDown(events.close);
    final link = ChangeLink();
    addTearDown(link.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              RepositoryProvider.value(value: client),
              RepositoryProvider.value(value: TextCopier((_) {})),
              BlocProvider.value(value: documents),
              BlocProvider.value(value: events),
            ],
            child: Row(
              children: [
                Expanded(child: EventsTab(onChange: link.open)),
                Expanded(
                  child: ChangesTab(
                    mirror: ChangeMirror(client, id),
                    link: link,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.text(EventsTab.empty), findsOneWidget);
    expect(find.text(EventsTab.recordingNote), findsOneWidget);

    await tester.tap(find.text('Record'));
    await settle(tester);
    text.insert(0, 'a');
    await settle(tester);
    expect(find.text('changes'), findsOneWidget);
    expect(find.text('created'), findsOneWidget);

    await tester.tap(find.text('changes'));
    await settle(tester);
    final change = doc.version.single.toString();
    expect(find.text('Event 0'), findsOneWidget);
    await tester.tap(find.text('→ $change'));
    await settle(tester);
    expect(find.text(ChangeDetail.frontierLabel), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await settle(tester);
    expect(find.text(EventsTab.empty), findsOneWidget);

    // Stopping cancels the lease renewal timer, which `testWidgets` checks.
    await tester.tap(find.text('Record'));
    await settle(tester);
    expect(events.state.recording, isFalse);

    await tester.pumpWidget(const SizedBox());
    doc.dispose();
    await settle(tester);
  });

  testWidgets('a failed Record shows the error and a retry', (tester) async {
    final bridge = InProcessBridge();
    addTearDown(bridge.dispose);
    final client = CrdtLfClient(bridge);
    // No document has this id, so every call fails.
    final events = EventLogCubit(client, 999);
    addTearDown(events.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(
            value: events,
            child: EventsTab(onChange: (_) {}),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Record'));
    await settle(tester);
    expect(find.textContaining('The call failed'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(find.textContaining('The call failed'), findsOneWidget);
    expect(events.state.recording, isFalse);
  });
}
