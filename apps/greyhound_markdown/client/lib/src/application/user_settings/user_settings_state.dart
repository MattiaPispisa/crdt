part of 'user_settings_cubit.dart';

/// The persisted preferences of the local user.
class UserSettingsState extends Equatable {
  /// Creates settings with every field given.
  const UserSettingsState({
    required this.name,
    required this.color,
    required this.themeMode,
    required this.showLineNumbers,
    required this.wordWrap,
  });

  /// The settings of a first visit: no name yet, a random palette color so two
  /// peers rarely collide, the platform's own light/dark preference, and the
  /// editor defaults (no gutter, lines wrapped).
  factory UserSettingsState.initial() {
    return UserSettingsState(
      name: '',
      color: kAvatarPalette[Random().nextInt(kAvatarPalette.length)],
      themeMode: ThemeMode.system,
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

  /// Whether the editor draws a line-number gutter next to the source.
  final bool showLineNumbers;

  /// Whether long editor lines wrap at the pane edge.
  ///
  /// When `false` a line runs as far as it needs to and the editor scrolls
  /// sideways.
  final bool wordWrap;

  /// [name], or [kDefaultUserName] while the user has not picked one.
  String get displayName => name.trim().isEmpty ? kDefaultUserName : name;

  /// A copy of these settings with the given fields replaced.
  UserSettingsState copyWith({
    String? name,
    Color? color,
    ThemeMode? themeMode,
    bool? showLineNumbers,
    bool? wordWrap,
  }) {
    return UserSettingsState(
      name: name ?? this.name,
      color: color ?? this.color,
      themeMode: themeMode ?? this.themeMode,
      showLineNumbers: showLineNumbers ?? this.showLineNumbers,
      wordWrap: wordWrap ?? this.wordWrap,
    );
  }

  @override
  List<Object?> get props => [
    name,
    color,
    themeMode,
    showLineNumbers,
    wordWrap,
  ];
}
