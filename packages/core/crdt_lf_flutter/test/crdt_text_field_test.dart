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

    testWidgets(
        'records a mid-caret edit next to an identical character on the '
        'caret side (does not slide past it)', (tester) async {
      // Regression: typing on the empty line between the fences of
      // "```dart\n```" used to attach the characters after the closing
      // newline, because the delta slid across the identical '\n'.
      final note = CRDTFugueTextHandler(doc, 'note')..insert(0, '```dart\n```');
      await tester.pumpWidget(host());
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;

      // Drive the controller as a real keystroke does (TextField writes the
      // new value + collapsed caret to its controller, firing the binding).
      void keystroke(int at, String ch) {
        controller.value = TextEditingValue(
          text: controller.text.replaceRange(at, at, ch),
          selection: TextSelection.collapsed(offset: at + ch.length),
        );
      }

      // Caret at the end of line 1 (before the existing '\n'), press Enter.
      keystroke(7, '\n');
      await tester.pump();

      // Type on the now-empty middle line.
      for (final ch in 'hi'.split('')) {
        keystroke(controller.selection.baseOffset, ch);
        await tester.pump();
      }

      expect(controller.text, '```dart\nhi\n```');
      expect(note.value, '```dart\nhi\n```');
    });

    testWidgets(
        'backspacing an emoji removes it whole (code-unit field offsets '
        'against rune handler indices)', (tester) async {
      final note = CRDTFugueTextHandler(doc, 'note');
      await tester.pumpWidget(host());
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;

      await tester.enterText(find.byType(TextField), 'a😀b');
      expect(note.value, 'a😀b');
      // One rune per element: the emoji is a single handler position even
      // though the field counts it as two code units.
      expect(note.length, 3);
      expect(controller.text.length, 4);

      // Backspace with the caret right after the emoji. Flutter deletes the
      // whole cluster, so the field hands us a two-code-unit deletion.
      controller.value = const TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 1),
      );
      await tester.pump();

      expect(note.value, 'ab');
      expect(controller.text, 'ab');
    });

    testWidgets('anchors the caret correctly past an emoji', (tester) async {
      CRDTFugueTextHandler(doc, 'note').insert(0, 'a😀b');
      await tester.pumpWidget(host());
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!
            // Caret at code-unit offset 3 — after the emoji, i.e. rune 2.
            ..selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();

      // A remote insertion before the caret must shift it by the inserted
      // code units, not by the inserted runes.
      final remote = remotePeer();
      (remote.registeredHandlers['note']! as CRDTFugueTextHandler)
          .insert(0, '🎉');
      doc.importChanges(remote.exportChanges());
      await tester.pump();

      expect(controller.text, '🎉a😀b');
      expect(controller.selection.baseOffset, 5);
    });

    testWidgets(
        'places the caret exactly across a multi-region remote edit on a '
        'CRDTTextHandler, which has no stable positions', (tester) async {
      // The Fugue test above is rescued by element identity. This handler has
      // none, so the caret rides on what the handler reported it did. A diff
      // of the two texts would collapse both regions into one span covering
      // the caret and snap it to the end.
      CRDTTextHandler(doc, 'note').insert(0, 'hello world');
      await tester.pumpWidget(host());
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
        ..selection = const TextSelection.collapsed(offset: 5);

      final remote = CRDTDocument(peerId: PeerId.generate());
      final remoteNote = CRDTTextHandler(remote, 'note');
      remote.importChanges(doc.exportChanges());
      remoteNote
        ..insert(0, 'A')
        ..insert(12, 'B');
      doc.importChanges(
        remote.exportChanges(fromVersionVector: doc.getVersionVector()),
      );
      await tester.pump();

      expect(controller.text, 'Ahello worldB');
      // Still right after "hello", shifted by the one character inserted
      // before it — not dragged to the end.
      expect(controller.selection.baseOffset, 6);
    });

    testWidgets('takes in a batch of changes one at a time', (tester) async {
      final note = CRDTFugueTextHandler(doc, 'note')..insert(0, 'hello');
      await tester.pumpWidget(host());
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;

      var writes = 0;
      controller.addListener(() => writes++);

      final remote = remotePeer();
      remote.registeredHandlers['note']! as CRDTFugueTextHandler
        ..insert(5, ' a')
        ..insert(7, ' b')
        ..insert(9, ' c');
      doc.importChanges(
        remote.exportChanges(fromVersionVector: doc.getVersionVector()),
      );
      await tester.pump();

      expect(controller.text, note.value);
      // One write per change, because each one now costs the size of its own
      // edit. Flutter folds them into a single frame anyway, which is why the
      // subtree still builds once.
      expect(writes, 3);
      expect(builds, 1);
    });

    testWidgets('never projects the document again while typing',
        (tester) async {
      // The point of the whole thing: the field moves its text with the
      // deltas, so `handler.value` — which rebuilds the entire string — is
      // never asked for.
      final note = _CountingFugueTextHandler(doc, 'note')..insert(0, 'hello');
      await tester.pumpWidget(host());
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;

      debugVerifyCrdtTextFieldProjection = false;
      addTearDown(() => debugVerifyCrdtTextFieldProjection = true);
      note.reads = 0;

      for (var i = 0; i < 5; i++) {
        final next = '${controller.text}x';
        controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
        await tester.pump();
      }

      expect(note.value, 'helloxxxxx');
      expect(controller.text, 'helloxxxxx');
      // `note.value` on the line above is the only read there was.
      expect(note.reads, 1);
    });

    testWidgets('never projects the document again for a remote change',
        (tester) async {
      final note = _CountingFugueTextHandler(doc, 'note')..insert(0, 'hello');
      await tester.pumpWidget(host());
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;

      final remote = remotePeer();
      final remoteNote =
          remote.registeredHandlers['note']! as CRDTFugueTextHandler;

      debugVerifyCrdtTextFieldProjection = false;
      addTearDown(() => debugVerifyCrdtTextFieldProjection = true);
      note.reads = 0;

      remoteNote.insert(5, '!');
      doc.importChanges(
        remote.exportChanges(fromVersionVector: doc.getVersionVector()),
      );
      await tester.pump();

      expect(controller.text, 'hello!');
      expect(note.reads, 0);
    });

    testWidgets('throws a FlutterError for a non-text handler', (tester) async {
      CRDTListHandler<String>(doc, 'note');
      await tester.pumpWidget(host());
      expect(tester.takeException(), isA<FlutterError>());
    });
  });
}

/// A Fugue text handler that counts how often its value is projected.
final class _CountingFugueTextHandler extends CRDTFugueTextHandler {
  _CountingFugueTextHandler(super.doc, super.id);

  int reads = 0;

  @override
  String get value {
    reads++;
    return super.value;
  }
}
