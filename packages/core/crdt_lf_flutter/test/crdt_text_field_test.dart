import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
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
        'merges a burst of remote changes arriving while a composition is '
        'pending', (tester) async {
      // A batch of changes is published at once and delivered one at a time.
      // Committing the pending composition on the first of them must not
      // account for the ones still on their way: they would be dropped, and
      // the field would keep text the document does not have.
      final note = CRDTFugueTextHandler(doc, 'note')..insert(0, 'hello world');
      await tester.pumpWidget(host());
      await tester.showKeyboard(find.byType(TextField));

      final remote = remotePeer();

      // Local composition in progress (uncommitted)...
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'hello worldX',
          selection: TextSelection.collapsed(offset: 12),
          composing: TextRange(start: 11, end: 12),
        ),
      );
      await tester.pump();
      expect(note.value, 'hello world');

      // ...while three changes land in one batch. The two after the first
      // replace one rune with another, so they are net-zero: a field that
      // dropped them would still hold the right *number* of runes, and the
      // cheap length check would agree.
      (remote.registeredHandlers['note']! as CRDTFugueTextHandler)
        ..insert(0, 'A')
        ..update(1, 'H')
        ..update(7, 'W');
      doc.importChanges(
        remote.exportChanges(fromVersionVector: doc.getVersionVector()),
      );
      await tester.pumpAndSettle();

      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      expect(note.value, 'AHello WorldX');
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
      final note = CRDTTextHandler(doc, 'note')..insert(0, 'hello ');
      await tester.pumpWidget(host());
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;

      // Typed through the field, so both arms of the push reach this handler
      // and not only the Fugue one.
      await tester.enterText(find.byType(TextField), 'hello brave world');
      expect(note.value, 'hello brave world');
      await tester.enterText(find.byType(TextField), 'hello world');
      expect(note.value, 'hello world');

      controller.selection = const TextSelection.collapsed(offset: 5);

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

    testWidgets('reads the value once when it mounts', (tester) async {
      // Seeding the field and answering the reset that opens the stream are
      // the same question, and the answer costs a projection of the whole
      // document. Asking it twice showed the same text twice.
      final note = _CountingFugueTextHandler(doc, 'note')
        ..insert(0, 'hello')
        ..reads = 0;

      debugVerifyCrdtTextFieldProjection = false;
      addTearDown(() => debugVerifyCrdtTextFieldProjection = true);

      await tester.pumpWidget(host());
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'hello',
      );
      expect(note.reads, 1);
    });

    testWidgets('shows an imported change before the import returns',
        (tester) async {
      // The document hands its events out as it settles, so there is no window
      // where the change exists and the field still paints the old text. A
      // keystroke needs no pump to land in the right place either.
      final note = CRDTFugueTextHandler(doc, 'note')..insert(0, 'hello');
      await tester.pumpWidget(host());
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;

      final remote = remotePeer();
      (remote.registeredHandlers['note']! as CRDTFugueTextHandler)
          .insert(0, 'X');
      doc.importChanges(
        remote.exportChanges(fromVersionVector: doc.getVersionVector()),
      );

      // Deliberately no pump.
      expect(controller.text, 'Xhello');

      final typed = '${controller.text}!';
      controller.value = TextEditingValue(
        text: typed,
        selection: TextSelection.collapsed(offset: typed.length),
      );
      await tester.pump();

      expect(note.value, 'Xhello!');
      expect(controller.text, note.value);
    });

    testWidgets('follows the handler when the id changes', (tester) async {
      CRDTFugueTextHandler(doc, 'note').insert(0, 'first');
      CRDTFugueTextHandler(doc, 'other').insert(0, 'second');

      await tester.pumpWidget(host());
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'first',
      );

      await tester.pumpWidget(host(id: 'other'));
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'second',
      );
    });

    testWidgets('keeps a pending IME composition across a remote change',
        (tester) async {
      final note = CRDTFugueTextHandler(doc, 'note')..insert(0, 'hello');
      await tester.pumpWidget(host());
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!
            // Mid-composition: the user is typing at the end, nothing
            // committed.
            ..value = const TextEditingValue(
              text: 'hellozz',
              selection: TextSelection.collapsed(offset: 7),
              composing: TextRange(start: 5, end: 7),
            );
      await tester.pump();

      final remote = remotePeer();
      (remote.registeredHandlers['note']! as CRDTFugueTextHandler)
          .insert(0, 'X');
      doc.importChanges(
        remote.exportChanges(fromVersionVector: doc.getVersionVector()),
      );
      await tester.pump();

      expect(controller.text, note.value);
      // The composed characters moved along with the text instead of being
      // thrown away under the user.
      expect(controller.value.composing.isValid, isTrue);
      expect(
        controller.text.substring(
          controller.value.composing.start,
          controller.value.composing.end,
        ),
        'zz',
      );
    });

    testWidgets('adopts a remote deletion', (tester) async {
      // The mirror of the insert cases above: text going away has to move the
      // field's copy the same way, and the caret with it.
      final note = CRDTFugueTextHandler(doc, 'note')..insert(0, 'hello world');
      await tester.pumpWidget(host());
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
        ..selection = const TextSelection.collapsed(offset: 11);

      final remote = remotePeer();
      (remote.registeredHandlers['note']! as CRDTFugueTextHandler)
          .delete(0, 6); // "hello "
      doc.importChanges(
        remote.exportChanges(fromVersionVector: doc.getVersionVector()),
      );
      await tester.pump();

      expect(controller.text, 'world');
      expect(note.value, 'world');
      // The caret was at the end and stays there, six characters earlier.
      expect(controller.selection.baseOffset, 5);
    });

    testWidgets('reads the value again when the handler asks for a reset',
        (tester) async {
      // A snapshot replaces the base the deltas were describing, so no delta
      // can say what moved. This is the recovery path, and the only one that
      // reads the whole value.
      CRDTFugueTextHandler(doc, 'note').insert(0, 'hello');
      await tester.pumpWidget(host());
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      expect(controller.text, 'hello');

      final other = CRDTDocument(peerId: PeerId.generate());
      CRDTFugueTextHandler(other, 'note').insert(0, 'something else');
      doc.importSnapshot(other.takeSnapshot());
      await tester.pump();

      expect(
        controller.text,
        (doc.registeredHandlers['note']! as CRDTFugueTextHandler).value,
      );
    });

    testWidgets('reads the handler back when its own text has drifted',
        (tester) async {
      // The field derives its text and never reads it back, so a handler that
      // under-reports would leave the wrong document on screen for good. The
      // handler below reports one character less than it applies, which is
      // exactly the mistake the check exists to catch.
      final note = _LyingFugueTextHandler(doc, 'note', _dropOneInserted)
        ..insert(0, 'hello');
      await tester.pumpWidget(host());
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;

      // The debug check compares the whole value and would throw first; this
      // test is about the cheap one that also runs in release.
      debugVerifyCrdtTextFieldProjection = false;
      addTearDown(() => debugVerifyCrdtTextFieldProjection = true);

      final remote = remotePeer();
      (remote.registeredHandlers['note']! as CRDTFugueTextHandler)
          .insert(5, 'XY');
      doc.importChanges(
        remote.exportChanges(fromVersionVector: doc.getVersionVector()),
      );
      await tester.pump();

      // The delta said one character, the handler holds two: the field noticed
      // and read instead of showing text the document does not have.
      expect(controller.text, note.value);
      expect(controller.text, 'helloXY');
    });

    testWidgets('cannot see a drift that keeps the rune count', (tester) async {
      // The counterpart of the test above, and the reason
      // [debugVerifyCrdtTextFieldProjection] exists. This handler reports the
      // right *number* of characters and the wrong ones, so the length is
      // intact — and length is all a `CRDTFugueTextHandler` is asked for,
      // because it answers that without projecting anything.
      final note = _LyingFugueTextHandler(doc, 'note', _swapOneInserted)
        ..insert(0, 'hello');
      await tester.pumpWidget(host());
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;

      debugVerifyCrdtTextFieldProjection = false;
      addTearDown(() => debugVerifyCrdtTextFieldProjection = true);

      final remote = remotePeer();
      (remote.registeredHandlers['note']! as CRDTFugueTextHandler)
          .insert(5, 'XY');
      doc.importChanges(
        remote.exportChanges(fromVersionVector: doc.getVersionVector()),
      );
      await tester.pump();

      // The check agreed, so the field kept text the document does not have.
      // Nothing in release closes this gap; the debug compare below does.
      expect(note.value, 'helloXY');
      expect(controller.text, 'helloQY');
    });

    testWidgets('recovers when the handler drops its cache during a push',
        (tester) async {
      // A handler with no incremental path invalidates on every operation, so
      // the field's own write comes back as a **reset** rather than a delta —
      // and it comes back while the write is still under way. A reset is not an
      // echo: what the push worked out describes a base that is gone, so it has
      // to read instead of trusting its own arithmetic.
      final note = CRDTFugueTextHandler(doc, 'note')
        ..insert(0, 'hello')
        ..useIncrementalCacheUpdate = false;
      await tester.pumpWidget(host());
      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!
            ..value = const TextEditingValue(
              text: 'helloX',
              selection: TextSelection.collapsed(offset: 6),
            );
      await tester.pumpAndSettle();

      expect(note.value, 'helloX');
      expect(controller.text, note.value);

      controller.value = const TextEditingValue(
        text: 'heloX',
        selection: TextSelection.collapsed(offset: 3),
      );
      await tester.pumpAndSettle();

      expect(note.value, 'heloX');
      expect(controller.text, note.value);
    });

    // More than one seed: one stream of random edits is one sample, and the
    // shapes that break this widget are rare enough that one sample misses
    // them.
    for (final seed in [7, 13, 29, 101, 997]) {
      testWidgets(
          'tracks a random stream of edits against the handler '
          '(seed $seed)', (tester) async {
        // `delta_oracle_test.dart` is the oracle for crdt_lf: it proves a
        // handler reports what it did. This is the same idea for the other
        // half — the bookkeeping this widget does on top of those reports,
        // which is the part no oracle covered and the part the burst bug
        // lived in.
        //
        // The field's text is derived and only checked against a rune count in
        // release, so a drift that keeps the count is invisible there. Here the
        // whole text is compared every round, which is what makes such a drift
        // fail loudly instead of quietly.
        final note = CRDTFugueTextHandler(doc, 'note')
          ..insert(0, 'hello world');
        await tester.pumpWidget(host());
        final controller =
            tester.widget<TextField>(find.byType(TextField)).controller!;

        final remote = remotePeer();
        final remoteNote =
            remote.registeredHandlers['note']! as CRDTFugueTextHandler;
        final random = Random(seed);
        var composing = false;

        for (var round = 0; round < 150; round++) {
          final text = controller.text;

          switch (random.nextInt(6)) {
            case 0:
            case 1:
              // A keystroke. Not while composing: the composed run is what the
              // next case commits.
              if (composing) {
                break;
              }
              final at = _runeBoundary(text, random.nextInt(text.length + 1));
              // An emoji now and then: the handlers index by rune, the field by
              // code unit, and that seam has been wrong before.
              final typed = random.nextInt(8) == 0
                  ? '😀'
                  : String.fromCharCode(97 + random.nextInt(26));
              controller.value = TextEditingValue(
                text: text.replaceRange(at, at, typed),
                selection: TextSelection.collapsed(offset: at + typed.length),
              );
            case 2:
              if (composing || text.isEmpty) {
                break;
              }
              final at = _runeBoundary(text, random.nextInt(text.length));
              // Whole rune: no editor ever deletes half a surrogate pair.
              final end = _runeBoundary(text, at + 1) == at
                  ? at + 2
                  : _nextRune(text, at);
              controller.value = TextEditingValue(
                text: text.replaceRange(at, end, ''),
                selection: TextSelection.collapsed(offset: at),
              );
            case 3:
              // Start an IME composition: uncommitted, so the handler must not
              // move until it ends or something remote forces the commit.
              if (composing) {
                break;
              }
              composing = true;
              controller.value = TextEditingValue(
                text: '${text}zz',
                selection: TextSelection.collapsed(offset: text.length + 2),
                composing: TextRange(start: text.length, end: text.length + 2),
              );
            case 4:
              if (!composing) {
                break;
              }
              composing = false;
              controller.value = TextEditingValue(
                text: text,
                selection: TextSelection.collapsed(offset: text.length),
              );
            case 5:
              // A batch of remote changes, published at once and handed out
              // one at a time. `update` replaces one rune with another, so
              // its delta is net-zero and the rune count cannot give a
              // dropped one away.
              if (random.nextBool()) {
                // Sometimes caught up (causal), sometimes behind (concurrent).
                final vector = remote.getVersionVector();
                remote.importChanges(
                  doc.exportChanges(fromVersionVector: vector),
                );
              }
              final count = 1 + random.nextInt(3);
              for (var i = 0; i < count; i++) {
                final length = remoteNote.length;
                switch (random.nextInt(3)) {
                  case 0:
                    remoteNote.insert(
                      random.nextInt(length + 1),
                      String.fromCharCode(65 + random.nextInt(26)),
                    );
                  case 1:
                    if (length > 0) {
                      remoteNote.delete(random.nextInt(length), 1);
                    }
                  case 2:
                    if (length > 0) {
                      remoteNote.update(
                        random.nextInt(length),
                        String.fromCharCode(65 + random.nextInt(26)),
                      );
                    }
                }
              }
              doc.importChanges(
                remote.exportChanges(fromVersionVector: doc.getVersionVector()),
              );
              // Taking a remote change in commits whatever was pending.
              composing = false;
          }

          await tester.pumpAndSettle();
          if (!composing) {
            expect(controller.text, note.value, reason: 'round $round');
          }
        }

        if (composing) {
          // End on a committed note, or the claim below is not the field's to
          // keep: while a composition is pending the two are meant to differ.
          controller.value = TextEditingValue(
            text: controller.text,
            selection: TextSelection.collapsed(offset: controller.text.length),
          );
          await tester.pumpAndSettle();
        }
        expect(controller.text, note.value);
      });
    }

    testWidgets('throws a FlutterError for a non-text handler', (tester) async {
      CRDTListHandler<String>(doc, 'note');
      await tester.pumpWidget(host());

      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      // This widget takes two named handlers, so it can name them. The
      // generic "wrong delta shape" message would be a worse answer.
      expect(
        error.toString(),
        contains('expected a CRDTTextHandler or CRDTFugueTextHandler'),
      );
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

/// The start of the rune that [offset] falls in.
int _runeBoundary(String text, int offset) {
  if (offset <= 0 || offset >= text.length) {
    return offset.clamp(0, text.length);
  }
  final unit = text.codeUnitAt(offset);
  return (unit >= 0xDC00 && unit <= 0xDFFF) ? offset - 1 : offset;
}

/// The end of the rune that starts at [at].
int _nextRune(String text, int at) {
  final unit = text.codeUnitAt(at);
  return (unit >= 0xD800 && unit <= 0xDBFF && at + 1 < text.length)
      ? at + 2
      : at + 1;
}

/// Rewrites a delta into the one a broken handler would report.
typedef _Lie = SequenceDelta<String> Function(SequenceDelta<String> delta);

/// A handler that reports something other than what it applies.
///
/// It exists to make the field's projection drift on purpose. Nothing else
/// can: every real handler reports exactly what it did, which is what
/// `delta_oracle_test.dart` proves.
final class _LyingFugueTextHandler extends CRDTFugueTextHandler {
  _LyingFugueTextHandler(super.doc, super.id, this.lie);

  /// How this handler misreports what it did.
  final _Lie lie;

  @override
  void applyToTree(
    FugueTree<String> tree,
    Operation operation, {
    DeltaSink<Object?>? sink,
  }) {
    if (sink == null) {
      super.applyToTree(tree, operation);
      return;
    }
    super.applyToTree(tree, operation, sink: _LyingSink(sink, lie));
  }
}

/// Passes every delta through [_lie] on its way out.
final class _LyingSink implements DeltaSink<Object?> {
  _LyingSink(this._inner, this._lie);

  final DeltaSink<Object?> _inner;
  final _Lie _lie;

  @override
  void add(Object? delta) {
    _inner.add(delta is SequenceDelta<String> ? _lie(delta) : delta);
  }
}

/// Drops one inserted element: a drift the rune count gives away.
SequenceDelta<String> _dropOneInserted(SequenceDelta<String> delta) =>
    SequenceDelta<String>([
      for (final op in delta.ops)
        if (op is SeqInsert<String> && op.values.length > 1)
          SeqInsert<String>(op.values.sublist(1))
        else
          op,
    ]);

/// Reports the right *number* of inserted elements and the wrong ones: a
/// drift the rune count cannot give away.
SequenceDelta<String> _swapOneInserted(SequenceDelta<String> delta) =>
    SequenceDelta<String>([
      for (final op in delta.ops)
        if (op is SeqInsert<String> && op.values.isNotEmpty)
          SeqInsert<String>(['Q', ...op.values.skip(1)])
        else
          op,
    ]);
