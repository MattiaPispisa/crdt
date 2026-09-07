part of 'user_settings_cubit.dart';

/// A room this device has opened, and when it last did.
///
/// The room id is the only name a document has, so this is what the home
/// screen shows as a way back in.
class RecentRoom extends Equatable {
  /// Creates an entry for [roomId], opened at [openedAt].
  const RecentRoom({required this.roomId, required this.openedAt});

  /// The room that was opened. It is also the document id.
  final String roomId;

  /// When the room was last opened, in UTC.
  final DateTime openedAt;

  @override
  List<Object?> get props => [roomId, openedAt];
}

/// The persisted preferences of the local user.
class UserSettingsState extends Equatable {
  /// Creates settings with every field given.
  const UserSettingsState({
    required this.name,
    required this.color,
    required this.themeMode,
    required this.language,
    required this.showLineNumbers,
    required this.wordWrap,
    this.recentRooms = const [],
  });

  /// The settings of a first visit: no name yet, a random palette color so two
  /// peers rarely collide, the platform's own light/dark and language
  /// preferences, and the editor defaults (no gutter, lines wrapped).
  factory UserSettingsState.initial() {
    return UserSettingsState(
      name: '',
      color: kAvatarPalette[Random().nextInt(kAvatarPalette.length)],
      themeMode: ThemeMode.system,
      language: AppLanguage.system,
      showLineNumbers: false,
      wordWrap: true,
    );
  }

  /// The name the user typed, empty until they pick one.
  final String name;

  /// The color of this peer's cursor and avatar, one of [kAvatarPalette].
  final Color color;

  /// Whether the app follows the system theme or is forced light/dark.
  final ThemeMode themeMode;

  /// Whether the app follows the system language or is forced to one.
  final AppLanguage language;

  /// Whether the editor draws a line-number gutter next to the source.
  final bool showLineNumbers;

  /// Whether long editor lines wrap at the pane edge.
  ///
  /// When `false` a line runs as far as it needs to and the editor scrolls
  /// sideways.
  final bool wordWrap;

  /// The rooms this device opened last, most recent first.
  ///
  /// At most [kRecentRoomsLimit] long, and a room appears once however many
  /// times it was opened.
  final List<RecentRoom> recentRooms;

  /// [name], or [kDefaultUserName] while the user has not picked one.
  String get displayName => name.trim().isEmpty ? kDefaultUserName : name;

  /// A copy of these settings with the given fields replaced.
  UserSettingsState copyWith({
    String? name,
    Color? color,
    ThemeMode? themeMode,
    AppLanguage? language,
    bool? showLineNumbers,
    bool? wordWrap,
    List<RecentRoom>? recentRooms,
  }) {
    return UserSettingsState(
      name: name ?? this.name,
      color: color ?? this.color,
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      showLineNumbers: showLineNumbers ?? this.showLineNumbers,
      wordWrap: wordWrap ?? this.wordWrap,
      recentRooms: recentRooms ?? this.recentRooms,
    );
  }

  @override
  List<Object?> get props => [
    name,
    color,
    themeMode,
    language,
    showLineNumbers,
    wordWrap,
    recentRooms,
  ];
}
