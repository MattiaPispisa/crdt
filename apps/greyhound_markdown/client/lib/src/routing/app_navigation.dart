import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:greyhound_markdown_client/src/routing/app_routes.dart';

/// One method per app route.
///
/// A `go` method replaces the page stack with the route and the pages above
/// Home on its path: any room left behind is closed. A `push` method puts the
/// page on top, so the page below stays open and Back returns to it.
extension AppNavigation on BuildContext {
  /// Goes to Home.
  void goHome() => goNamed(AppRoute.home);

  /// Goes into the room named [roomId].
  void goRoom(String roomId) => goNamed(
    AppRoute.room,
    pathParameters: {AppRoute.roomIdParameter: roomId},
  );

  /// Goes to Settings.
  void goSettings() => goNamed(AppRoute.settings);

  /// Goes to the changelog, with Settings below it.
  void goChangelog() => goNamed(AppRoute.changelog);

  /// Opens Settings on top of the current page; completes when it is popped.
  Future<void> pushSettings() => pushNamed(AppRoute.settings);

  /// Opens the changelog on top of the current page; completes when it is
  /// popped.
  Future<void> pushChangelog() => pushNamed(AppRoute.changelog);
}
