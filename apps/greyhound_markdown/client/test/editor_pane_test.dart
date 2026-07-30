import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/services/awareness_service.dart';
import 'package:greyhound_markdown_client/src/widgets/editor_pane.dart';

/// A document plus an awareness service wired like [EditorScreen] does.
///
/// The (never connected) relay client is what attaches the awareness plugin;
/// without it every cursor publication throws, since the plugin reads its
/// client as soon as the selection moves.
({CRDTDocument document, AwarenessService awareness}) _room() {
  final document = CRDTDocument(peerId: PeerId.generate());
  CRDTFugueTextHandler(document, kHandlerId);
  final awareness = AwarenessService(name: 'me', color: Colors.teal);
  final sync = WebSocketRelayClient(
    url: 'ws://localhost',
    document: document,
    author: document.peerId,
    plugins: [awareness.plugin],
  );
  addTearDown(sync.dispose);
  addTearDown(awareness.dispose);
  addTearDown(document.dispose);
  return (document: document, awareness: awareness);
}

void main() {
  testWidgets('empty editor shows the welcome as a scrollable placeholder that '
      'disappears once the document has content', (tester) async {
    final room = _room();

    await tester.pumpWidget(
      CrdtProvider.value(
        value: room.document,
        child: MaterialApp(
          home: Scaffold(body: EditorPane(awareness: room.awareness)),
        ),
      ),
    );

    // The whole welcome is rendered, inside a scroll view (not a clipped hint).
    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.text(kPlaceholderMarkdown),
      ),
      findsOneWidget,
    );

    // Typing removes the placeholder.
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    expect(find.text(kPlaceholderMarkdown), findsNothing);

    // Let the awareness throttle timer drain before teardown.
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('the platform chord applies the matching toolbar action', (
    tester,
  ) async {
    final room = _room();

    await tester.pumpWidget(
      CrdtProvider.value(
        value: room.document,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Scaffold(body: EditorPane(awareness: room.awareness)),
        ),
      ),
    );

    // Focus the field directly: the empty-document placeholder sits on top of
    // it and would swallow the tap.
    await tester.showKeyboard(find.byType(TextField));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '****');
    expect(field.controller!.selection.baseOffset, 2);

    await tester.pump(const Duration(milliseconds: 100));
  });
}
