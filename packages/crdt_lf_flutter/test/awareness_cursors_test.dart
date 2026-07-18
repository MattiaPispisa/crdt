import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrdtAwarenessCursorsOverlay', () {
    testWidgets(
        'draws a marker at the normalized position and reports the '
        'local pointer', (tester) async {
      const cursor = CrdtAwarenessCursor(
        id: 'peer-b',
        color: Color(0xFFAA0000),
        label: 'Bob',
        position: Offset(0.5, 0.25),
      );
      final reported = <(Offset, bool)>[];

      await tester.pumpWidget(
        MaterialApp(
          home: CrdtAwarenessCursorsOverlay(
            cursors: const [cursor],
            onLocalPointer: (position, {required hovering}) =>
                reported.add((position, hovering)),
            child: const ColoredBox(color: Color(0xFFFFFFFF)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The remote marker sits at `position * size` with its name bubble.
      expect(find.text('Bob'), findsOneWidget);
      final size = tester.getSize(find.byType(CrdtAwarenessCursorsOverlay));
      final positioned = tester.widget<AnimatedPositioned>(
        find.byType(AnimatedPositioned),
      );
      expect(positioned.left, size.width * .5);
      expect(positioned.top, size.height * .25);

      // Hovering reports the normalized local pointer; leaving the pane
      // reports hovering: false.
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(Offset(size.width * .5, size.height * .5));
      await tester.pump();
      expect(reported.last, (const Offset(0.5, 0.5), true));

      await gesture.moveTo(const Offset(-10, -10));
      await tester.pump();
      expect(reported.last.$2, isFalse);
    });
  });

  group('CrdtAwarenessCursorsBuilder', () {
    testWidgets('positions each cursor and delegates its look to builder',
        (tester) async {
      const cursors = [
        CrdtAwarenessCursor(
          id: 'a',
          color: Color(0xFF00FF00),
          position: Offset(0.25, 0.75),
        ),
        CrdtAwarenessCursor(
          id: 'b',
          color: Color(0xFF0000FF),
          position: Offset(0.5, 0.5),
        ),
      ];
      final seen = <Object>[];

      await tester.pumpWidget(
        MaterialApp(
          home: CrdtAwarenessCursorsBuilder(
            cursors: cursors,
            builder: (context, cursor) {
              seen.add(cursor.id);
              return SizedBox(key: ValueKey('marker-${cursor.id}'));
            },
            child: const ColoredBox(color: Color(0xFFFFFFFF)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The builder ran once per cursor.
      expect(seen, ['a', 'b']);
      final size = tester.getSize(find.byType(CrdtAwarenessCursorsBuilder));
      final a = tester.widget<AnimatedPositioned>(
        find.ancestor(
          of: find.byKey(const ValueKey('marker-a')),
          matching: find.byType(AnimatedPositioned),
        ),
      );
      expect(a.left, size.width * 0.25);
      expect(a.top, size.height * 0.75);
    });
  });

  group('CrdtAwarenessCursorMarker', () {
    testWidgets('styles the name bubble text through CrdtAwarenessCursorStyle',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CrdtAwarenessCursorMarker(
            label: 'Bob',
            style: const CrdtAwarenessCursorStyle(
              color: Color(0xFFAA0000),
              labelStyle: TextStyle(color: Color(0xFF112233), fontSize: 20),
            ),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('Bob'));
      // labelStyle is merged over the default (white/11/w600): overrides win,
      // the unspecified weight is inherited.
      expect(text.style!.color, const Color(0xFF112233));
      expect(text.style!.fontSize, 20);
      expect(text.style!.fontWeight, FontWeight.w600);
    });

    test('rejects providing both color and style', () {
      expect(
        () => CrdtAwarenessCursorMarker(
          color: const Color(0xFFAA0000),
          style: const CrdtAwarenessCursorStyle(),
        ),
        throwsAssertionError,
      );
    });
  });
}
