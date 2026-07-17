import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:crdt_lf_flutter_example/shared/text_presence_hub.dart';
import 'package:crdt_lf_flutter_example/simulated_sync_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_examples_infrastructure/shared_examples_infrastructure.dart';

void main() {
  testWidgets(
    'typing in one peer pane shows its labelled text cursor in the other',
    (tester) async {
      // Wide surface so both peer panes are laid out side by side.
      tester.view.physicalSize = const Size(1800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final network = Network()..setOnlineStatus(true);
      final hub = TextPresenceHub();
      final authors = [PeerId.generate(), PeerId.generate()];
      final screen = documentExample(
        sessionsFactory:
            () => [
              for (final (index, author) in authors.indexed)
                SimulatedSyncSession(
                  author: author,
                  network: network,
                  label: 'Peer ${index + 1}',
                  textPresence: hub.register(
                    peerId: author.toString(),
                    label: 'Peer ${index + 1}',
                  ),
                ),
            ],
      );
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pumpAndSettle();

      // Add a chapter from Peer 1's pane (the first add FAB + dialog).
      await tester.tap(find.byType(FloatingActionButton).first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Intro',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();

      // Type into Peer 1's chapter-title field: the selection anchors are
      // published on the hub and must reach Peer 2's overlay — and only
      // Peer 2's (a peer never sees its own cursor).
      await tester.enterText(
        find.widgetWithText(TextField, 'Intro').first,
        'Introduction',
      );
      await tester.pumpAndSettle();

      final overlays =
          tester
              .widgetList<CrdtTextCursorsOverlay>(
                find.byType(CrdtTextCursorsOverlay),
              )
              .toList();
      final withCursor =
          overlays.where((overlay) => overlay.cursors.isNotEmpty).toList();
      expect(withCursor, hasLength(1));
      expect(withCursor.single.cursors.single.label, 'Peer 1');
    },
  );
}
