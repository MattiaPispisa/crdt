import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/routing/app_navigation.dart';
import 'package:greyhound_markdown_client/src/screens/changelog_screen.dart';
import 'package:greyhound_markdown_client/src/screens/settings_screen.dart';

import 'helpers/router_app.dart';

/// Pumps until a page transition is over.
///
/// Not `pumpAndSettle`: the changelog shows a spinner until its asset loads,
/// and that load may still be pending under the test's fake clock.
Future<void> _pumpPastTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('AppNavigation', () {
    testWidgets('each go method lands on its route', (tester) async {
      final router = await pumpRouterApp(tester);

      contextOf(router).goRoom('abc123');
      await tester.pumpAndSettle();
      expect(locationOf(router), '/room/abc123');

      contextOf(router).goSettings();
      await tester.pumpAndSettle();
      expect(locationOf(router), '/settings');

      contextOf(router).goChangelog();
      await _pumpPastTransition(tester);
      expect(locationOf(router), '/settings/changelog');

      contextOf(router).goHome();
      await tester.pumpAndSettle();
      expect(locationOf(router), '/');
    });

    testWidgets('settings and changelog pushed from a room return to it', (
      tester,
    ) async {
      final router = await pumpRouterApp(
        tester,
        initialLocation: '/room/abc123',
      );

      contextOf(router).pushSettings();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      contextOf(router).pushChangelog();
      await _pumpPastTransition(tester);
      expect(find.byType(ChangelogScreen), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();

      expect(locationOf(router), '/room/abc123');
      expect(find.text('room abc123'), findsOneWidget);
    });
  });
}
