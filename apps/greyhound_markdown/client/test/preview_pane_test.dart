import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/widgets/preview_pane.dart';

({CRDTDocument document, CRDTFugueTextHandler text}) _room() {
  final document = CRDTDocument(peerId: PeerId.generate());
  final text = CRDTFugueTextHandler(document, kHandlerId);
  addTearDown(document.dispose);
  return (document: document, text: text);
}

Future<void> _pump(WidgetTester tester, CRDTDocument document) {
  return tester.pumpWidget(
    CrdtProvider.value(
      value: document,
      child: const MaterialApp(home: Scaffold(body: PreviewPane())),
    ),
  );
}

void main() {
  testWidgets('an empty document shows the welcome placeholder', (
    tester,
  ) async {
    final room = _room();
    await _pump(tester, room.document);

    expect(find.textContaining('Greyhound Markdown'), findsWidgets);
  });

  testWidgets('renders the document on the first frame, without waiting', (
    tester,
  ) async {
    final room = _room()..text.insert(0, 'already here');
    await _pump(tester, room.document);

    expect(find.textContaining('already here'), findsOneWidget);
  });

  testWidgets('an edit only reaches the preview after the debounce', (
    tester,
  ) async {
    final room = _room()..text.insert(0, 'first');
    await _pump(tester, room.document);

    room.text
      ..insert(5, ' second')
      ..insert(12, ' third');
    await tester.pump();

    // Still the old render: the two edits cost one parse, not two.
    expect(find.textContaining('first second third'), findsNothing);
    expect(find.textContaining('first'), findsOneWidget);

    await tester.pump(kPreviewDebounce);
    expect(find.textContaining('first second third'), findsOneWidget);
  });
}
