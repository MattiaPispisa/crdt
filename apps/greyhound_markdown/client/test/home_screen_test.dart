import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';

import 'helpers/router_app.dart';

/// The field labelled [label].
Finder _field(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextField));

final _nameField = _field('Your name');
final _roomField = _field('Room id');

/// Whether the field labelled [label] currently holds the caret.
bool _isFocused(WidgetTester tester, String label) {
  return tester
      .widget<EditableText>(
        find.descendant(
          of: find.ancestor(
            of: find.text(label),
            matching: find.byType(TextField),
          ),
          matching: find.byType(EditableText),
        ),
      )
      .focusNode
      .hasFocus;
}

void main() {
  group('HomeScreen', () {
    testWidgets('focuses the name on a first visit', (tester) async {
      await pumpRouterApp(tester);

      expect(_isFocused(tester, 'Your name'), isTrue);
      expect(_isFocused(tester, 'Room id'), isFalse);
    });

    testWidgets('leaves the focus alone when the name is already known', (
      tester,
    ) async {
      await pumpRouterApp(tester, stored: {'name': 'Ada'});

      expect(find.widgetWithText(TextField, 'Ada'), findsOneWidget);
      // Nothing left to fill in, so nothing grabs the caret — no keyboard
      // pops up on a returning visitor.
      expect(_isFocused(tester, 'Your name'), isFalse);
      expect(_isFocused(tester, 'Room id'), isFalse);
    });

    testWidgets('typing a room id moves the emphasis onto Join', (
      tester,
    ) async {
      await pumpRouterApp(tester);

      // Nothing to join yet: creating is the only live action.
      expect(find.widgetWithText(FilledButton, 'Join'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Join'))
            .onPressed,
        isNull,
      );
      expect(
        find.widgetWithText(FilledButton, 'Create a new room'),
        findsOneWidget,
      );

      await tester.enterText(_roomField, 'abc123');
      await tester.pump();

      expect(find.widgetWithText(FilledButton, 'Join'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Create a new room'),
        findsOneWidget,
      );
    });

    testWidgets('enter joins the room that is typed', (tester) async {
      final router = await pumpRouterApp(tester);

      // Upper case and blanks are copy/paste noise, not a different room.
      await tester.enterText(_roomField, '  AbC123  ');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();

      expect(locationOf(router), '/room/abc123');
    });

    testWidgets('enter creates a room when none is named', (tester) async {
      final router = await pumpRouterApp(tester);

      // Not a room id — pressing enter still has to lead somewhere.
      await tester.enterText(_roomField, '??');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();

      final segments = router.state.uri.pathSegments;
      expect(segments.first, 'room');
      expect(parseRoomId(segments.last), isNotNull);
    });

    testWidgets('a recently opened room leads back into it', (tester) async {
      final router = await pumpRouterApp(
        tester,
        stored: {
          'recentRooms': <Object>[
            {'roomId': 'abc123', 'openedAt': 1000},
          ],
        },
      );

      // The list sits at the bottom of a scrolling page.
      await tester.ensureVisible(find.text('abc123'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('abc123'));
      await tester.pumpAndSettle();

      expect(locationOf(router), '/room/abc123');
    });

    testWidgets('enter on the name field goes in too', (tester) async {
      final router = await pumpRouterApp(tester);

      await tester.enterText(_nameField, 'Ada');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();

      expect(router.state.uri.pathSegments.first, 'room');
    });
  });
}
