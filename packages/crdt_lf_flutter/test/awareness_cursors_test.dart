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
}
