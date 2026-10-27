// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/screens/history_screen.dart';
import 'package:greyhound_markdown_client/src/widgets/preview_pane.dart';

import 'helpers/localized_app.dart';
import 'helpers/memory_storage.dart';

({CRDTDocument document, CRDTFugueTextHandler text}) _room() {
  final document = CRDTDocument(peerId: PeerId.generate());
  final text = CRDTFugueTextHandler(document, kHandlerId);
  addTearDown(document.dispose);
  return (document: document, text: text);
}

Future<void> _pump(WidgetTester tester, CRDTDocument document) {
  return tester.pumpWidget(
    BlocProvider(
      create: (_) => UserSettingsCubit(storage: MemoryStorage()),
      child: CrdtProvider.value(
        value: document,
        child: localizedApp(const HistoryScreen()),
      ),
    ),
  );
}

/// Waits for the preview to render what the cursor moved to.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(kPreviewDebounce);
}

String _info(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('history-change-info'))).data!;

void main() {
  group('HistoryScreen', () {
    testWidgets('opens on the latest change, made by this device', (
      tester,
    ) async {
      final room = _room();
      room.text
        ..insert(0, 'one')
        ..insert(3, ' two');
      await _pump(tester, room.document);

      expect(find.textContaining('one two'), findsOneWidget);
      expect(find.text('Change 2 of 2'), findsOneWidget);
      expect(_info(tester), startsWith('You · '));
    });

    testWidgets('moves through the changes with the buttons and the slider', (
      tester,
    ) async {
      final room = _room();
      room.text
        ..insert(0, 'one')
        ..insert(3, ' two')
        ..insert(7, ' three');
      await _pump(tester, room.document);

      await tester.tap(find.byTooltip('Previous change'));
      await _settle(tester);
      expect(find.text('Change 2 of 3'), findsOneWidget);
      expect(find.textContaining('one two'), findsOneWidget);
      expect(find.textContaining('three'), findsNothing);

      tester.widget<Slider>(find.byKey(const Key('history-slider'))).onChanged!(
        0,
      );
      await _settle(tester);
      expect(find.text('Change 0 of 3'), findsOneWidget);
      expect(_info(tester), 'Initial state');
      // Blank, not the welcome text: nobody wrote it in the document.
      expect(find.textContaining('one'), findsNothing);
      expect(find.textContaining('Greyhound Markdown'), findsNothing);

      await tester.tap(find.byTooltip('Next change'));
      await _settle(tester);
      expect(find.textContaining('one'), findsOneWidget);
    });

    testWidgets('names a short peer id when someone else made the change', (
      tester,
    ) async {
      final room = _room()..text.insert(0, 'mine');
      final other = CRDTDocument(peerId: PeerId.generate());
      addTearDown(other.dispose);
      final theirs = CRDTFugueTextHandler(other, kHandlerId);
      // Their edit follows ours, so it is the last of the history.
      other.importChanges(room.document.exportChanges());
      theirs.insert(4, ' and theirs');
      room.document.importChanges(other.exportChanges());
      await _pump(tester, room.document);

      expect(_info(tester), isNot(startsWith('You')));
      expect(_info(tester), matches(RegExp('^[0-9a-f]{8} · ')));
    });

    testWidgets('says so when there is nothing to browse', (tester) async {
      final room = _room();
      await _pump(tester, room.document);

      expect(find.text('No changes yet'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
    });
  });
}
