// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:flutter/widgets.dart';
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

      contextOf(router).goHome();
      await tester.pumpAndSettle();
      expect(locationOf(router), '/');

      contextOf(router).goSettings();
      await tester.pumpAndSettle();
      expect(locationOf(router), '/settings');

      contextOf(router).goChangelog();
      await _pumpPastTransition(tester);
      expect(locationOf(router), '/settings/changelog');
      expect(reportedLocationOf(router), '/settings/changelog');

      contextOf(router).goHome();
      await tester.pumpAndSettle();
      expect(locationOf(router), '/');
    });

    testWidgets('the history opens over the room and returns to it', (
      tester,
    ) async {
      final router = await pumpRouterApp(
        tester,
        initialLocation: '/room/abc123',
      );

      contextOf(router).goHistory('abc123');
      await tester.pumpAndSettle();
      expect(locationOf(router), '/room/abc123/history');
      // What the address bar shows, so the link opens the same page.
      expect(reportedLocationOf(router), '/room/abc123/history');
      expect(find.text('history abc123'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      expect(locationOf(router), '/room/abc123');
      expect(reportedLocationOf(router), '/room/abc123');
      expect(find.text('room abc123'), findsOneWidget);
    });

    testWidgets('the room shell stays open from the editor to the history', (
      tester,
    ) async {
      final shells = <_ShellProbeState>[];
      final router = await pumpRouterApp(
        tester,
        initialLocation: '/room/abc123',
        roomShell: (roomId, child) =>
            _ShellProbe(roomId: roomId, onState: shells.add, child: child),
      );
      expect(shells, hasLength(1));
      expect(shells.single.roomId, 'abc123');

      contextOf(router).goHistory('abc123');
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();

      // The same state all along: nothing was opened again.
      expect(shells, hasLength(1));
      expect(shells.single.mounted, isTrue);

      // Another room reaches the same shell state with its own id: the real
      // shell keys what it opens by that id.
      contextOf(router).goRoom('other1');
      await tester.pumpAndSettle();
      expect(shells, hasLength(1));
      expect(shells.single.roomId, 'other1');
    });

    testWidgets('settings and changelog from a room keep it open', (
      tester,
    ) async {
      final shells = <_ShellProbeState>[];
      final router = await pumpRouterApp(
        tester,
        initialLocation: '/room/abc123',
        roomShell: (roomId, child) =>
            _ShellProbe(roomId: roomId, onState: shells.add, child: child),
      );

      contextOf(router).goSettings();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(locationOf(router), '/room/abc123/settings');
      expect(reportedLocationOf(router), '/room/abc123/settings');

      contextOf(router).goChangelog();
      await _pumpPastTransition(tester);
      expect(find.byType(ChangelogScreen), findsOneWidget);
      expect(reportedLocationOf(router), '/room/abc123/settings/changelog');

      router.pop();
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();

      expect(locationOf(router), '/room/abc123');
      expect(find.text('room abc123'), findsOneWidget);
      // The room was never closed on the way.
      expect(shells, hasLength(1));
      expect(shells.single.mounted, isTrue);
    });
  });
}

/// A room shell that records its state, to tell a shell kept open from one
/// built again.
class _ShellProbe extends StatefulWidget {
  const _ShellProbe({
    required this.roomId,
    required this.onState,
    required this.child,
  });

  final String roomId;
  final void Function(_ShellProbeState state) onState;
  final Widget child;

  @override
  State<_ShellProbe> createState() => _ShellProbeState();
}

class _ShellProbeState extends State<_ShellProbe> {
  String get roomId => widget.roomId;

  @override
  void initState() {
    super.initState();
    widget.onState(this);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
