import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/screens/changelog_screen.dart';
import 'package:greyhound_markdown_client/src/screens/home_screen.dart';

import 'helpers/router_app.dart';

void main() {
  group('createAppRouter', () {
    testWidgets('opens a room link with Home underneath', (tester) async {
      final router = await pumpRouterApp(
        tester,
        initialLocation: '/room/abc123',
      );

      expect(locationOf(router), '/room/abc123');
      expect(find.text('room abc123'), findsOneWidget);
      expect(router.canPop(), isTrue);
    });

    testWidgets('normalizes a hand-edited room id', (tester) async {
      final router = await pumpRouterApp(
        tester,
        initialLocation: '/room/AbC123',
      );

      expect(locationOf(router), '/room/abc123');
    });

    testWidgets('sends a link that names no room to Home', (tester) async {
      for (final location in ['/room/ab', '/room/a%20b', '/room/room!']) {
        final router = await pumpRouterApp(tester, initialLocation: location);

        expect(locationOf(router), '/', reason: location);
        expect(find.byType(HomeScreen), findsOneWidget, reason: location);
      }
    });

    testWidgets('sends an unknown path to Home', (tester) async {
      final router = await pumpRouterApp(tester, initialLocation: '/nope');

      expect(locationOf(router), '/');
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('keeps the old changelog link working', (tester) async {
      final router = await pumpRouterApp(tester, initialLocation: '/changelog');

      expect(locationOf(router), '/settings/changelog');
      expect(find.byType(ChangelogScreen), findsOneWidget);
    });
  });
}
