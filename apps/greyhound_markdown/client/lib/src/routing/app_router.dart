import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/routing/app_routes.dart';
import 'package:greyhound_markdown_client/src/screens/changelog_screen.dart';
import 'package:greyhound_markdown_client/src/screens/editor_screen.dart';
import 'package:greyhound_markdown_client/src/screens/home_screen.dart';
import 'package:greyhound_markdown_client/src/screens/settings_screen.dart';

/// The router of the app, starting at [initialLocation].
///
/// Every page sits above Home, so a shared link still has a way back. A room
/// link goes through [parseRoomId]: `/room/AbC123` becomes `/room/abc123`,
/// and an id that names no room leads Home. So does any unknown path. The old
/// `/changelog` link leads to `/settings/changelog`.
///
/// [roomBuilder] builds the page of a room; tests replace the editor, which
/// needs a relay.
GoRouter createAppRouter({
  String initialLocation = '/',
  Widget Function(String roomId) roomBuilder = _editorScreen,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    onException: (_, _, router) => router.goNamed(AppRoute.home),
    routes: [
      GoRoute(
        path: '/',
        name: AppRoute.home,
        builder: (_, _) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'room/:${AppRoute.roomIdParameter}',
            name: AppRoute.room,
            redirect: _normalizeRoomId,
            builder: (_, state) =>
                roomBuilder(state.pathParameters[AppRoute.roomIdParameter]!),
          ),
          GoRoute(
            path: 'settings',
            name: AppRoute.settings,
            builder: (_, _) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'changelog',
                name: AppRoute.changelog,
                builder: (_, _) => const ChangelogScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/changelog',
        redirect: (_, state) => state.namedLocation(AppRoute.changelog),
      ),
    ],
  );
}

Widget _editorScreen(String roomId) => EditorScreen(roomId: roomId);

String? _normalizeRoomId(BuildContext context, GoRouterState state) {
  final raw = state.pathParameters[AppRoute.roomIdParameter]!;
  final roomId = parseRoomId(raw);
  if (roomId == null) {
    return state.namedLocation(AppRoute.home);
  }
  if (roomId == raw) {
    return null;
  }
  return state.namedLocation(
    AppRoute.room,
    pathParameters: {AppRoute.roomIdParameter: roomId},
  );
}
