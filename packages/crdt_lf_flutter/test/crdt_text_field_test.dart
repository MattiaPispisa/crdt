import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrdtTextFieldBuilder', () {
    late CRDTDocument doc;
    var builds = 0;

    Widget host({String id = 'note'}) {
      return CrdtProvider.value(
        value: doc,
        child: MaterialApp(
          home: Scaffold(
            body: CrdtTextFieldBuilder(
              id: id,
              builder: (context, controller) {
                builds++;
                return TextField(controller: controller);
              },
            ),
          ),
        ),
      );
    }

    setUp(() {
      doc = CRDTDocument(peerId: PeerId.generate());
      builds = 0;
    });

    /// A remote peer that shares [doc]'s history, so its edit positions are
    /// deterministic after the merge.
    CRDTDocument remotePeer() {
      final remote = CRDTDocument(peerId: PeerId.generate());
      CRDTFugueTextHandler(remote, 'note');
      remote.importChanges(doc.exportChanges());
      return remote;
    }

    testWidgets('pushes local edits into the handler as they happen',
        (tester) async {
      final note = CRDTFugueTextHandler(doc, 'note');
      await tester.pumpWidget(host());

      await tester.enterText(find.byType(TextField), 'hello');
      expect(note.value, 'hello');

      // Edit in the middle: the delta targets the gesture, not the whole text.
      await tester.enterText(find.byType(TextField), 'heXYllo');
      expect(note.value, 'heXYllo');
    });

    testWidgets(
        'adopts a remote change in place, mapping the caret through it '
        '— without rebuilding', (tester) async {
      CRDTFugueTextHandler(doc, 'note').insert(0, 'hello world');
      await tester.pumpWidget(host());
      expect(builds, 1);

      // Focus and put the caret after "hello".
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
        ..selection = const TextSelection.collapsed(offset: 5);

      // A remote peer prepends text.
      final remote = remotePeer();
      (remote.registeredHandlers['note']! as CRDTFugueTextHandler)
          .insert(0, 'XXX ');
      doc.importChanges(remote.exportChanges());
      await tester.pump();

      expect(controller.text, 'XXX hello world');
      // The caret is still after "hello": shifted by the remote insertion.
      expect(controller.selection.baseOffset, 9);
      // The subtree never rebuilt: the controller was updated in place.
      expect(builds, 1);
    });

    testWidgets(
        'keeps the caret anchored across a multi-region remote edit '
        '(stable positions, where a text delta alone would misplace it)',
        (tester) async {
      CRDTFugueTextHandler(doc, 'note').insert(0, 'hello world');
      await tester.pumpWidget(host());
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
        ..selection = const TextSelection.collapsed(offset: 5);

      // One remote change touching BOTH ends: the single contiguous delta
      // spans the caret, so pure delta mapping would snap it to the end.
      final remote = remotePeer();
      (remote.registeredHandlers['note']! as CRDTFugueTextHandler)
        ..insert(0, 'A')
        ..insert(12, 'B');
      doc.importChanges(remote.exportChanges());
      await tester.pump();

      expect(controller.text, 'Ahello worldB');
      // Still right after "hello": the anchor follows the element identity.
      expect(controller.selection.baseOffset, 6);
    });

    testWidgets('defers commits while an IME composition is active',
        (tester) async {
      final note = CRDTFugueTextHandler(doc, 'note');
      await tester.pumpWidget(host());
      await tester.showKeyboard(find.byType(TextField));

      // Composing (e.g. CJK input): nothing is committed yet.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'nihao',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        ),
      );
      await tester.pump();
      expect(note.value, '');

      // Composition ends: the accumulated delta is committed once.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '你好',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      expect(note.value, '你好');
    });

    testWidgets(
        'merges a remote change arriving while a composition is pending',
        (tester) async {
      final note = CRDTFugueTextHandler(doc, 'note')..insert(0, 'hello');
      await tester.pumpWidget(host());
      await tester.showKeyboard(find.byType(TextField));

      final remote = remotePeer();

      // Local composition in progress (uncommitted)...
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'helloX',
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange(start: 5, end: 6),
        ),
      );
      await tester.pump();
      expect(note.value, 'hello');

      // ...while a remote edit lands: the pending text is committed and
      // merged instead of being lost.
      (remote.registeredHandlers['note']! as CRDTFugueTextHandler)
          .insert(0, 'A ');
      doc.importChanges(remote.exportChanges());
      await tester.pumpAndSettle();

      expect(note.value, contains('A '));
      expect(note.value, contains('X'));
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      expect(controller.text, note.value);
    });

    testWidgets('throws a FlutterError for a non-text handler', (tester) async {
      CRDTListHandler<String>(doc, 'note');
      await tester.pumpWidget(host());
      expect(tester.takeException(), isA<FlutterError>());
    });
  });
}
