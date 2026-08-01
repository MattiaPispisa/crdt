import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greyhound_markdown_client/src/screens/changelog_screen.dart';

void main() {
  testWidgets('renders the bundled changelog asset as markdown', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ChangelogScreen()));
    // First frame: FutureBuilder is still loading the asset.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Let rootBundle.loadString resolve and the markdown render.
    await tester.pumpAndSettle();

    expect(find.byType(Markdown), findsOneWidget);
    // The bundled asset is what got rendered — asserted on the data rather
    // than on painted text, which only covers the top of a long changelog.
    final markdown = tester.widget<Markdown>(find.byType(Markdown));
    expect(markdown.data, contains('Initial release'));
  });
}
