import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_flutter_example/simulated/network.dart';
import 'package:crdt_lf_flutter_example/simulated/simulated_sync.dart';
import 'package:factory_example/factory_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'typing in one peer pane shows its labelled text cursor in the other',
    (tester) async {
      // Wide surface so both peer panes are laid out side by side.
      tester.view.physicalSize = const Size(1800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final network = SimulatedNetwork()..setOnlineStatus(true);
      addTearDown(network.dispose);
      await tester.pumpWidget(
        ExampleApp(
          title: 'Examples',
          logo: const SizedBox.shrink(),
          links: const AppBarLinks(docsUrl: '', pubDevUrl: '', pubTooltip: ''),
          primaryColor: Colors.red,
          sync: SimulatedSync(network: network),
        ),
      );
      await tester.tap(find.text('Document'));
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
