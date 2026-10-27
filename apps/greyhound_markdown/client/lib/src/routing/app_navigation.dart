// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:greyhound_markdown_client/src/routing/app_routes.dart';

extension AppNavigation on BuildContext {
  /// Goes to Home.
  void goHome() => goNamed(AppRoute.home);

  /// Goes into the room named [roomId].
  void goRoom(String roomId) => goNamed(
    AppRoute.room,
    pathParameters: {AppRoute.roomIdParameter: roomId},
  );

  /// Goes to the history of the room named [roomId], with its editor below.
  /// The room stays open.
  void goHistory(String roomId) => goNamed(
    AppRoute.history,
    pathParameters: {AppRoute.roomIdParameter: roomId},
  );

  /// Goes to Settings. From a room it goes to the Settings of that room, and
  /// the room stays open below.
  void goSettings() => _goInRoomOr(AppRoute.roomSettings, AppRoute.settings);

  /// Goes to the changelog, with Settings below it. From a room it goes to the
  /// changelog of that room, and the room stays open below.
  void goChangelog() => _goInRoomOr(AppRoute.roomChangelog, AppRoute.changelog);

  /// Goes to [inRoom] when a room is open, to [outside] otherwise.
  void _goInRoomOr(String inRoom, String outside) {
    final roomId = GoRouter.of(
      this,
    ).state.pathParameters[AppRoute.roomIdParameter];
    if (roomId == null) {
      goNamed(outside);
      return;
    }
    goNamed(inRoom, pathParameters: {AppRoute.roomIdParameter: roomId});
  }
}
