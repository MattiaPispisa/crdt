import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:greyhound_markdown_client/src/screens/changelog_screen.dart';

void main() {
  testWidgets('renders the bundled changelog asset as markdown', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ChangelogScreen()),
    );
    // First frame: FutureBuilder is still loading the asset.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Let rootBundle.loadString resolve and the markdown render.
    await tester.pumpAndSettle();

    expect(find.byType(Markdown), findsOneWidget);
    // A heading from CHANGELOG.md proves the asset loaded and parsed.
    expect(find.textContaining('Initial release'), findsOneWidget);
  });
}
