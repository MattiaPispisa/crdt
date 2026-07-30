import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/screens/home_screen.dart';

import 'helpers/memory_storage.dart';

/// Pumps the home screen over settings restored from [stored], collecting the
/// routes it navigates to.
Future<List<String>> _pumpHome(
  WidgetTester tester, {
  Map<String, dynamic>? stored,
}) async {
  final storage = MemoryStorage(
    stored == null ? null : {'UserSettings': stored},
  );
  final pushed = <String>[];
  await tester.pumpWidget(
    BlocProvider(
      create: (_) => UserSettingsCubit(storage: storage),
      child: MaterialApp(
        onGenerateRoute: (settings) {
          final name = settings.name ?? '/';
          if (name != '/') pushed.add(name);
          return MaterialPageRoute<void>(
            settings: settings,
            // The editor needs a relay it must not reach from a test; the
            // route name is the whole point here.
            builder: (_) => name == '/'
                ? const HomeScreen()
                : const Scaffold(body: Text('room')),
          );
        },
      ),
    ),
  );
  return pushed;
}

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
      await _pumpHome(tester);

      expect(_isFocused(tester, 'Your name'), isTrue);
      expect(_isFocused(tester, 'Room id'), isFalse);
    });

    testWidgets('leaves the focus alone when the name is already known', (
      tester,
    ) async {
      await _pumpHome(tester, stored: {'name': 'Ada'});

      expect(find.widgetWithText(TextField, 'Ada'), findsOneWidget);
      // Nothing left to fill in, so nothing grabs the caret — no keyboard
      // pops up on a returning visitor.
      expect(_isFocused(tester, 'Your name'), isFalse);
      expect(_isFocused(tester, 'Room id'), isFalse);
    });

    testWidgets('typing a room id moves the emphasis onto Join', (
      tester,
    ) async {
      await _pumpHome(tester);

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
      final pushed = await _pumpHome(tester);

      // Upper case and blanks are copy/paste noise, not a different room.
      await tester.enterText(_roomField, '  AbC123  ');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();

      expect(pushed, ['/room/abc123']);
    });

    testWidgets('enter creates a room when none is named', (tester) async {
      final pushed = await _pumpHome(tester);

      // Not a room id — pressing enter still has to lead somewhere.
      await tester.enterText(_roomField, '??');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();

      expect(pushed, hasLength(1));
      expect(parseRoomId(pushed.single.split('/').last), isNotNull);
    });

    testWidgets('enter on the name field goes in too', (tester) async {
      final pushed = await _pumpHome(tester);

      await tester.enterText(_nameField, 'Ada');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();

      expect(pushed, hasLength(1));
    });
  });
}
