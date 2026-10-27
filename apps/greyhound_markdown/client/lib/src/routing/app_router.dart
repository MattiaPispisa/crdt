// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/di/service_locator.dart';
import 'package:greyhound_markdown_client/src/logging/app_logger.dart';
import 'package:greyhound_markdown_client/src/routing/app_routes.dart';
import 'package:greyhound_markdown_client/src/screens/changelog_screen.dart';
import 'package:greyhound_markdown_client/src/screens/editor_screen.dart';
import 'package:greyhound_markdown_client/src/screens/history_screen.dart';
import 'package:greyhound_markdown_client/src/screens/home_screen.dart';
import 'package:greyhound_markdown_client/src/screens/settings_screen.dart';
import 'package:greyhound_markdown_client/src/widgets/room_shell.dart';

/// The router of the app, starting at [initialLocation].
///
/// Every page sits above Home, so a shared link still has a way back. A room
/// link goes through [parseRoomId]: `/room/AbC123` becomes `/room/abc123`,
/// and an id that names no room leads Home. So does any unknown path. The old
/// `/changelog` link leads to `/settings/changelog`.
///
/// Every location change, redirect and unknown path is logged under
/// [LogScope.router].
///
/// A room is a shell: [roomShell] opens the room and keeps it open while
/// its pages, the editor and the history, replace each other inside it.
/// [roomBuilder] and [historyBuilder] build those two pages. Tests replace all
/// three, because opening a room needs a relay.
GoRouter createAppRouter({
  String initialLocation = '/',
  Widget Function(String roomId, Widget child) roomShell = _roomShell,
  Widget Function(String roomId) roomBuilder = _editorScreen,
  Widget Function(String roomId) historyBuilder = _historyScreen,
}) {
  final logger = loggerFor(LogScope.router);
  final router = GoRouter(
    initialLocation: initialLocation,
    onException: (_, state, router) {
      logger.warning('Unknown location ${state.uri}, going home');
      router.goNamed(AppRoute.home);
    },
    routes: [
      GoRoute(
        path: '/',
        name: AppRoute.home,
        builder: (_, _) => const HomeScreen(),
        routes: [
          ShellRoute(
            builder: (_, state, child) => roomShell(
              state.pathParameters[AppRoute.roomIdParameter]!,
              child,
            ),
            routes: [
              GoRoute(
                path: 'room/:${AppRoute.roomIdParameter}',
                name: AppRoute.room,
                redirect: _normalizeRoomId,
                builder: (_, state) => roomBuilder(
                  state.pathParameters[AppRoute.roomIdParameter]!,
                ),
                routes: [
                  GoRoute(
                    path: 'history',
                    name: AppRoute.history,
                    builder: (_, state) => historyBuilder(
                      state.pathParameters[AppRoute.roomIdParameter]!,
                    ),
                  ),
                  // Settings again, under the room: reached from a room, it
                  // leaves the room open.
                  _settingsRoute(
                    settings: AppRoute.roomSettings,
                    changelog: AppRoute.roomChangelog,
                  ),
                ],
              ),
            ],
          ),
          _settingsRoute(
            settings: AppRoute.settings,
            changelog: AppRoute.changelog,
          ),
        ],
      ),
      GoRoute(
        path: '/changelog',
        redirect: (_, state) => state.namedLocation(AppRoute.changelog),
      ),
    ],
  );
  router.routeInformationProvider.addListener(
    () => logger.info('Location ${router.routeInformationProvider.value.uri}'),
  );
  return router;
}

/// Settings and the changelog under it, named [settings] and [changelog].
GoRoute _settingsRoute({required String settings, required String changelog}) {
  return GoRoute(
    path: 'settings',
    name: settings,
    builder: (_, _) => const SettingsScreen(),
    routes: [
      GoRoute(
        path: 'changelog',
        name: changelog,
        builder: (_, _) => const ChangelogScreen(),
      ),
    ],
  );
}

Widget _roomShell(String roomId, Widget child) =>
    RoomShell(roomId: roomId, child: child);

Widget _editorScreen(String roomId) => EditorScreen(roomId: roomId);

Widget _historyScreen(String roomId) => const HistoryScreen();

String? _normalizeRoomId(BuildContext context, GoRouterState state) {
  final raw = state.pathParameters[AppRoute.roomIdParameter]!;
  final roomId = parseRoomId(raw);
  final logger = loggerFor(LogScope.router);
  if (roomId == null) {
    logger.warning('Invalid room id "$raw", going home');
    return state.namedLocation(AppRoute.home);
  }
  if (roomId == raw) {
    return null;
  }
  logger.info('Room id "$raw" normalized to "$roomId"');
  // Only the id changes, so a history link stays a history link.
  return state.uri
      .replace(path: state.uri.path.replaceFirst('/room/$raw', '/room/$roomId'))
      .toString();
}
