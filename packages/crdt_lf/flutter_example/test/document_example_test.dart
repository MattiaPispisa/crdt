import 'package:crdt_lf_flutter_example/examples/document/document_example.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Document example builds, adds chapter/paragraph/item', (
    tester,
  ) async {
    await tester.pumpWidget(
      const NetworkProvider(child: MaterialApp(home: DocumentExample())),
    );

    // Fills the open AddItemDialog and confirms it.
    Future<void> fillDialog(String text) async {
      final field = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, text);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
    }

    expect(find.text('CRDT LF: Document'), findsOneWidget);
    expect(
      find.text('No chapters yet. Add one using the button below!'),
      findsNWidgets(2),
    );

    // Add a chapter on the left pane via its FAB.
    await tester.tap(find.byType(FloatingActionButton).first);
    await tester.pumpAndSettle();
    await fillDialog('Intro');
    expect(find.text('Chapter 1'), findsOneWidget);

    // Add a paragraph to the new chapter.
    await tester.tap(find.text('Add paragraph'));
    await tester.pumpAndSettle();
    await fillDialog('Hello world');
    expect(find.text('Add item'), findsOneWidget);

    // Add an item to the new paragraph.
    await tester.tap(find.text('Add item'));
    await tester.pumpAndSettle();
    await fillDialog('First item');

    // The item drag handle (sortable list) is now present.
    expect(find.byIcon(Icons.drag_handle), findsOneWidget);
  });
}
