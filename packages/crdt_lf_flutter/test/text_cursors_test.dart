import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrdtTextCursorsOverlay', () {
    late CRDTDocument doc;

    setUp(() {
      doc = CRDTDocument(peerId: PeerId.generate());
    });

    Widget host(List<CrdtTextCursor> cursors) {
      return CrdtProvider.value(
        value: doc,
        child: MaterialApp(
          home: Scaffold(
            body: CrdtTextFieldBuilder(
              id: 'note',
              builder: (context, controller) => CrdtTextCursorsOverlay(
                id: 'note',
                cursors: cursors,
                child: TextField(controller: controller),
              ),
            ),
          ),
        ),
      );
    }

    /// The overlay's own [CustomPaint] (the `TextField` subtree contains
    /// unrelated ones).
    Finder overlayPaint() => find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter.runtimeType.toString() == '_TextCursorsPainter',
        );

    /// The caret rect the overlay is expected to draw for [offset], computed
    /// from the same render objects the painter uses.
    Rect expectedCaret(WidgetTester tester, int offset) {
      final editable =
          tester.allRenderObjects.whereType<RenderEditable>().first;
      final overlayBox = tester.renderObject(
        find.byType(CrdtTextCursorsOverlay),
      );
      final caret = MatrixUtils.transformRect(
        editable.getTransformTo(overlayBox),
        editable.getLocalRectForCaret(TextPosition(offset: offset)),
      );
      return Rect.fromLTWH(caret.left, caret.top, 2, caret.height);
    }

    testWidgets(
        'draws a caret at the anchored position and follows it '
        'across a remote edit', (tester) async {
      final note = CRDTFugueTextHandler(doc, 'note')..insert(0, 'hello world');
      const color = Color(0xFFAA0000);
      final cursor = CrdtTextCursor(
        id: 'peer-b',
        color: color,
        base: note.stablePositionAt(5), // after "hello"
      );
      await tester.pumpWidget(host([cursor]));

      expect(
        overlayPaint(),
        paints..rect(rect: expectedCaret(tester, 5), color: color),
      );

      // A remote peer (shared history) prepends text: the anchor keeps
      // pointing after "hello" and the painted caret moves with it.
      final remote = CRDTDocument(peerId: PeerId.generate());
      CRDTFugueTextHandler(remote, 'note');
      remote.importChanges(doc.exportChanges());
      (remote.registeredHandlers['note']! as CRDTFugueTextHandler)
          .insert(0, 'XXX ');
      doc.importChanges(remote.exportChanges());
      await tester.pump();

      expect(
        overlayPaint(),
        paints..rect(rect: expectedCaret(tester, 9), color: color),
      );
    });

    testWidgets('paints a selection highlight and a label tag', (tester) async {
      final note = CRDTFugueTextHandler(doc, 'note')..insert(0, 'hello world');
      const color = Color(0xFF00AA00);
      final cursor = CrdtTextCursor(
        id: 'peer-b',
        color: color,
        label: 'Bob',
        base: note.stablePositionAt(0),
        extent: note.stablePositionAt(5), // "hello" selected
      );
      await tester.pumpWidget(host([cursor]));

      expect(
        overlayPaint(),
        paints
          ..rect(color: color.withValues(alpha: .3)) // highlight
          ..rect(rect: expectedCaret(tester, 5), color: color) // caret
          ..rrect(color: color), // label tag
      );
    });

    testWidgets('hides a cursor whose anchor is not known yet', (tester) async {
      CRDTFugueTextHandler(doc, 'note').insert(0, 'hello');
      final cursor = CrdtTextCursor(
        id: 'peer-b',
        color: const Color(0xFF0000AA),
        // An element from a change this document has not received.
        base: FugueElementID(PeerId.generate(), 7),
      );
      await tester.pumpWidget(host([cursor]));

      expect(overlayPaint(), isNot(paints..rect()));
    });

    testWidgets('throws a FlutterError for a non-Fugue handler',
        (tester) async {
      CRDTListHandler<String>(doc, 'note');
      await tester.pumpWidget(host(const []));
      expect(tester.takeException(), isA<FlutterError>());
    });
  });

  group('resolveTextCursorLabelRect', () {
    const labelSize = Size(38, 14);
    const bounds = Size(300, 40);

    test('auto: above the caret, flipped below when it would be cut', () {
      // Plenty of room above.
      final tall = resolveTextCursorLabelRect(
        labelSize: labelSize,
        caret: const Rect.fromLTWH(100, 30, 2, 24),
        bounds: const Size(300, 200),
        placement: CrdtTextCursorLabelPlacement.auto,
      );
      expect(tall.top, 30 - 14 - 4);

      // First line of a dense field: no room above → below the caret.
      final dense = resolveTextCursorLabelRect(
        labelSize: labelSize,
        caret: const Rect.fromLTWH(100, 8, 2, 24),
        bounds: bounds,
        placement: CrdtTextCursorLabelPlacement.auto,
      );
      expect(dense.top, 8 + 24 + 4);
    });

    test('forced placements are honored even outside the field', () {
      final above = resolveTextCursorLabelRect(
        labelSize: labelSize,
        caret: const Rect.fromLTWH(100, 8, 2, 24),
        bounds: bounds,
        placement: CrdtTextCursorLabelPlacement.above,
      );
      expect(above.top, lessThan(0)); // escapes the field, never cut
      final below = resolveTextCursorLabelRect(
        labelSize: labelSize,
        caret: const Rect.fromLTWH(100, 8, 2, 24),
        bounds: bounds,
        placement: CrdtTextCursorLabelPlacement.below,
      );
      expect(below.top, 8 + 24 + 4);
    });

    test('clamps horizontally into the field', () {
      final nearEdge = resolveTextCursorLabelRect(
        labelSize: labelSize,
        caret: const Rect.fromLTWH(290, 8, 2, 24),
        bounds: bounds,
        placement: CrdtTextCursorLabelPlacement.auto,
      );
      expect(nearEdge.left, 300 - 38);
      expect(nearEdge.right, 300);
    });
  });

  group('CrdtTextFieldBuilder.onSelectionAnchorsChanged', () {
    testWidgets('publishes the anchors of the local selection', (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final note = CRDTFugueTextHandler(doc, 'note')..insert(0, 'hello');
      final published = <(FugueElementID?, FugueElementID?)>[];

      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: MaterialApp(
            home: Scaffold(
              body: CrdtTextFieldBuilder(
                id: 'note',
                onSelectionAnchorsChanged: (base, extent) =>
                    published.add((base, extent)),
                builder: (context, controller) =>
                    TextField(controller: controller),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      tester.widget<TextField>(find.byType(TextField)).controller!.selection =
          const TextSelection.collapsed(offset: 3);
      await tester.pump();

      expect(published, isNotEmpty);
      final (base, extent) = published.last;
      expect(base, note.stablePositionAt(3));
      expect(extent, note.stablePositionAt(3));
    });

    testWidgets('withdraws the anchors when the field loses focus',
        (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTFugueTextHandler(doc, 'a').insert(0, 'first');
      CRDTFugueTextHandler(doc, 'b').insert(0, 'second');
      final publishedA = <(FugueElementID?, FugueElementID?)>[];
      final publishedB = <(FugueElementID?, FugueElementID?)>[];

      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  CrdtTextFieldBuilder(
                    id: 'a',
                    onSelectionAnchorsChanged: (base, extent) =>
                        publishedA.add((base, extent)),
                    builder: (context, controller) =>
                        TextField(key: const Key('a'), controller: controller),
                  ),
                  CrdtTextFieldBuilder(
                    id: 'b',
                    onSelectionAnchorsChanged: (base, extent) =>
                        publishedB.add((base, extent)),
                    builder: (context, controller) =>
                        TextField(key: const Key('b'), controller: controller),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('a')));
      await tester.pump();
      expect(publishedA.last.$1, isNotNull);

      // Moving focus to the other field: Flutter keeps field a's selection
      // in its controller, but its published cursor must be withdrawn — a
      // user has one text cursor.
      await tester.tap(find.byKey(const Key('b')));
      await tester.pump();
      expect(publishedA.last, (null, null));
      expect(publishedB.last.$1, isNotNull);
    });
  });
}
