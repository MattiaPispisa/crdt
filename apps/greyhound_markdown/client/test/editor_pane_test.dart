import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/services/awareness_service.dart';
import 'package:greyhound_markdown_client/src/widgets/editor_pane.dart';

void main() {
  testWidgets(
      'empty editor shows the welcome as a scrollable placeholder that '
      'disappears once the document has content', (tester) async {
    final doc = CRDTDocument(peerId: PeerId.generate());
    CRDTFugueTextHandler(doc, kHandlerId);
    final awareness = AwarenessService(name: 'me', color: Colors.teal);
    addTearDown(awareness.dispose);
    addTearDown(doc.dispose);

    await tester.pumpWidget(
      CrdtProvider.value(
        value: doc,
        child: MaterialApp(
          home: Scaffold(body: EditorPane(awareness: awareness)),
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
}
