import 'package:en_logger/en_logger.dart';

/// An area of the app with its own logger and log prefix.
///
/// Get the logger of an area with `loggerFor`.
enum LogScope {
  /// Startup and app-wide setup.
  app('App'),

  /// Navigation: locations, redirects, unknown paths.
  router('Router'),

  /// Opening and closing a room, and its local storage.
  room('Room'),

  /// The relay client and its connection status.
  sync('Sync'),

  /// Peers joining and leaving a room.
  awareness('Awareness'),

  /// Changes to the user's settings.
  settings('Settings'),

  /// Exported files.
  export('Export');

  const LogScope(this.prefix);

  /// The prefix of every log of this area.
  final String prefix;
}

/// The root logger of the app: it writes to the developer console with
/// `[SNAKE_CASE]` prefixes.
///
/// The developer console is empty in a web release build, so logs show only
/// in debug builds there.
EnLogger createAppLogger() {
  return EnLogger(defaultPrefixFormat: const PrefixFormat.snakeSquare())
    ..addHandler(DevLogHandler());
}
