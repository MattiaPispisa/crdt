// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

/// The names of the app routes, for `goNamed` and `pushNamed`.
///
/// Navigate with the `AppNavigation` extension rather than with these names.
abstract final class AppRoute {
  /// `/`: create, join or reopen a room.
  static const String home = 'home';

  /// `/room/:roomId`: the editor of one room.
  static const String room = 'room';

  /// `/room/:roomId/history`: the version history of one room.
  static const String history = 'history';

  /// `/settings`: preferences, links and version.
  static const String settings = 'settings';

  /// `/settings/changelog`: the bundled changelog.
  static const String changelog = 'changelog';

  /// `/room/:roomId/settings`: [settings] reached from a room, which stays
  /// open below it.
  static const String roomSettings = 'room-settings';

  /// `/room/:roomId/settings/changelog`: [changelog] reached from a room.
  static const String roomChangelog = 'room-changelog';

  /// The path parameter of [room] that holds the room id.
  static const String roomIdParameter = 'roomId';
}
