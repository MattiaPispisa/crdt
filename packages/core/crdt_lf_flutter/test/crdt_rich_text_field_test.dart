import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle? _style(String type, Object value) {
  switch (type) {
    case 'bold':
      return const TextStyle(fontWeight: FontWeight.bold);
    case 'italic':
      return const TextStyle(fontStyle: FontStyle.italic);
    case 'link':
      return const TextStyle(decoration: TextDecoration.underline);
    default:
      return null;
  }
}

void main() {
  group('CrdtRichTextFieldBuilder', () {
    late CRDTDocument doc;
    var builds = 0;
    CrdtRichTextController? controller;

    Widget host({String id = 'body'}) {
      return CrdtProvider.value(
        value: doc,
        child: MaterialApp(
          home: Scaffold(
            body: CrdtRichTextFieldBuilder(
              id: id,
              resolveMarkStyle: _style,
              builder: (context, c) {
                builds++;
                controller = c;
                return TextField(controller: c, maxLines: null);
              },
            ),
          ),
        ),
      );
    }

    setUp(() {
      doc = CRDTDocument(peerId: PeerId.generate());
      builds = 0;
      controller = null;
    });

    /// A remote peer sharing [doc]'s history, so merge positions are
    /// deterministic.
    CRDTDocument remotePeer() {
      final remote = CRDTDocument(peerId: PeerId.generate());
      CRDTRichTextHandler(remote, 'body');
      remote.importChanges(doc.exportChanges());
      return remote;
    }

    testWidgets('pushes local edits into the handler as they happen',
        (tester) async {
      final body = CRDTRichTextHandler(doc, 'body');
      await tester.pumpWidget(host());

      await tester.enterText(find.byType(TextField), 'hello');
      expect(body.text, 'hello');

      await tester.enterText(find.byType(TextField), 'heXYllo');
      expect(body.text, 'heXYllo');
    });

    testWidgets('seeds the formatting already there, without rebuilding',
        (tester) async {
      CRDTRichTextHandler(doc, 'body')
        ..insert(0, 'hello world')
        ..addMark(start: 0, end: 5, type: 'bold', value: true);

      await tester.pumpWidget(host());

      expect(controller!.text, 'hello world');
      expect(controller!.spans, hasLength(1));
      expect(controller!.spans.single.type, 'bold');
      expect(builds, 1);
    });

    testWidgets('a remote mark reaches the controller without a rebuild',
        (tester) async {
      CRDTRichTextHandler(doc, 'body')..insert(0, 'hello world');
      await tester.pumpWidget(host());
      expect(builds, 1);

      final remote = remotePeer();
      final remoteBody =
          remote.registeredHandlers['body']! as CRDTRichTextHandler
            ..addMark(start: 6, end: 11, type: 'italic', value: true);
      doc.importChanges(
        remote.exportChanges(fromVersionVector: doc.getVersionVector()),
      );
      await tester.pumpAndSettle();

      expect(controller!.spans, hasLength(1));
      expect(controller!.spans.single.type, 'italic');
      expect(controller!.spans.single.start, 6);
      expect(builds, 1);
      expect(remoteBody.text, 'hello world');
    });

    testWidgets('toggleMark writes the selection into the document',
        (tester) async {
      final body = CRDTRichTextHandler(doc, 'body')..insert(0, 'hello world');
      await tester.pumpWidget(host());

      controller!.selection =
          const TextSelection(baseOffset: 0, extentOffset: 5);
      controller!.toggleMark('bold', value: true);
      await tester.pumpAndSettle();

      expect(body.value.spans, hasLength(1));
      expect(controller!.activeMarks, contains('bold'));

      // Toggling again takes it off.
      controller!.toggleMark('bold', value: true);
      await tester.pumpAndSettle();
      expect(body.value.spans, isEmpty);
      expect(controller!.activeMarks, isEmpty);
    });

    testWidgets('a collapsed selection marks nothing', (tester) async {
      final body = CRDTRichTextHandler(doc, 'body')..insert(0, 'hello');
      await tester.pumpWidget(host());

      controller!.selection = const TextSelection.collapsed(offset: 2);
      controller!.applyMark('bold', value: true);
      await tester.pumpAndSettle();

      expect(body.value.spans, isEmpty);
    });

    testWidgets('buildTextSpan paints one styled run per mark',
        (tester) async {
      CRDTRichTextHandler(doc, 'body')
        ..insert(0, 'abcdef')
        ..addMark(start: 2, end: 4, type: 'bold', value: true);
      await tester.pumpWidget(host());

      final span = controller!.buildTextSpan(
        context: tester.element(find.byType(TextField)),
        withComposing: false,
      );
      final runs = span.children!.cast<TextSpan>();
      expect(runs.map((r) => r.text), ['ab', 'cd', 'ef']);
      expect(runs[0].style?.fontWeight, isNull);
      expect(runs[1].style?.fontWeight, FontWeight.bold);
      expect(runs[2].style?.fontWeight, isNull);
    });

    testWidgets('overlapping marks of different types merge their styles',
        (tester) async {
      CRDTRichTextHandler(doc, 'body')
        ..insert(0, 'abcdef')
        ..addMark(start: 0, end: 4, type: 'bold', value: true)
        ..addMark(start: 2, end: 6, type: 'italic', value: true);
      await tester.pumpWidget(host());

      final span = controller!.buildTextSpan(
        context: tester.element(find.byType(TextField)),
        withComposing: false,
      );
      final runs = span.children!.cast<TextSpan>();
      expect(runs.map((r) => r.text), ['ab', 'cd', 'ef']);
      expect(runs[1].style?.fontWeight, FontWeight.bold);
      expect(runs[1].style?.fontStyle, FontStyle.italic);
    });

    testWidgets('text with no formatting is painted as one plain run',
        (tester) async {
      CRDTRichTextHandler(doc, 'body').insert(0, 'plain');
      await tester.pumpWidget(host());

      final span = controller!.buildTextSpan(
        context: tester.element(find.byType(TextField)),
        withComposing: false,
      );
      expect(span.text, 'plain');
    });

    testWidgets('an emoji does not shift the styled run', (tester) async {
      CRDTRichTextHandler(doc, 'body')
        ..insert(0, 'a😀bc')
        // Runes: a=0, emoji=1, b=2, c=3. Bold over 'bc'.
        ..addMark(start: 2, end: 4, type: 'bold', value: true);
      await tester.pumpWidget(host());

      final span = controller!.buildTextSpan(
        context: tester.element(find.byType(TextField)),
        withComposing: false,
      );
      final runs = span.children!.cast<TextSpan>();
      expect(runs.map((r) => r.text), ['a😀', 'bc']);
      expect(runs[1].style?.fontWeight, FontWeight.bold);
    });

    testWidgets('throws a FlutterError for a handler of another type',
        (tester) async {
      CRDTFugueTextHandler(doc, 'body');
      await tester.pumpWidget(host());
      expect(tester.takeException(), isA<FlutterError>());
    });

    for (final seed in [7, 13, 29, 101, 997]) {
      testWidgets(
          'tracks a random stream of edits and marks against the handler '
          '(seed $seed)', (tester) async {
        // The counterpart of `delta_oracle_test.dart`'s rich text group: that
        // one proves the handler reports what it did, this one proves the
        // widget's bookkeeping on top of those reports — the text it derives
        // and the spans it mirrors.
        final body = CRDTRichTextHandler(doc, 'body')
          ..insert(0, 'hello world');
        await tester.pumpWidget(host());
        final field = controller!;

        final remote = remotePeer();
        final remoteBody =
            remote.registeredHandlers['body']! as CRDTRichTextHandler;
        final random = Random(seed);
        const types = ['bold', 'italic', 'link'];

        for (var round = 0; round < 120; round++) {
          final text = field.text;

          switch (random.nextInt(5)) {
            case 0:
              final at = random.nextInt(text.length + 1);
              final typed = String.fromCharCode(97 + random.nextInt(26));
              field.value = TextEditingValue(
                text: text.replaceRange(at, at, typed),
                selection: TextSelection.collapsed(offset: at + 1),
              );
            case 1:
              if (text.isEmpty) {
                break;
              }
              final at = random.nextInt(text.length);
              field.value = TextEditingValue(
                text: text.replaceRange(at, at + 1, ''),
                selection: TextSelection.collapsed(offset: at),
              );
            case 2:
              // A local mark, through the controller's own API.
              if (text.length < 2) {
                break;
              }
              final start = random.nextInt(text.length - 1);
              field.selection = TextSelection(
                baseOffset: start,
                extentOffset: start + 1 + random.nextInt(text.length - start),
              );
              field.toggleMark(
                types[random.nextInt(types.length)],
                value: true,
                expand: random.nextBool(),
              );
            case 3:
            case 4:
              // A batch from the network: text and marks together.
              if (random.nextBool()) {
                remote.importChanges(
                  doc.exportChanges(
                    fromVersionVector: remote.getVersionVector(),
                  ),
                );
              }
              final count = 1 + random.nextInt(3);
              for (var i = 0; i < count; i++) {
                final length = remoteBody.length;
                switch (random.nextInt(3)) {
                  case 0:
                    remoteBody.insert(
                      random.nextInt(length + 1),
                      String.fromCharCode(65 + random.nextInt(26)),
                    );
                  case 1:
                    if (length > 0) {
                      remoteBody.delete(random.nextInt(length), 1);
                    }
                  case 2:
                    if (length > 1) {
                      final start = random.nextInt(length - 1);
                      remoteBody.addMark(
                        start: start,
                        end: start + 1 + random.nextInt(length - start - 1),
                        type: types[random.nextInt(types.length)],
                        value: true,
                      );
                    }
                }
              }
              doc.importChanges(
                remote.exportChanges(
                  fromVersionVector: doc.getVersionVector(),
                ),
              );
          }

          await tester.pumpAndSettle();
          expect(field.text, body.text, reason: 'text, round $round');
          expect(
            field.spans,
            body.value.spans,
            reason: 'spans, round $round',
          );
        }

        expect(builds, 1);
      });
    }
  });
}
