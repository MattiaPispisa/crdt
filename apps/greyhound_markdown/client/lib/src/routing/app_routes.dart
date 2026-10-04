/// The names of the app routes, for `goNamed` and `pushNamed`.
///
/// Navigate with the `AppNavigation` extension rather than with these names.
abstract final class AppRoute {
  /// `/`: create, join or reopen a room.
  static const String home = 'home';

  /// `/room/:roomId`: the editor of one room.
  static const String room = 'room';

  /// `/settings`: preferences, links and version.
  static const String settings = 'settings';

  /// `/settings/changelog`: the bundled changelog.
  static const String changelog = 'changelog';

  /// The path parameter of [room] that holds the room id.
  static const String roomIdParameter = 'roomId';
}
