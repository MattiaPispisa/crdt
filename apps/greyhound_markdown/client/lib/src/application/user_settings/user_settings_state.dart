part of 'user_settings_cubit.dart';

/// The persisted preferences of the local user.
class UserSettingsState extends Equatable {
  /// Creates settings with every field given.
  const UserSettingsState({
    required this.name,
    required this.color,
    required this.themeMode,
  });

  /// The settings of a first visit: no name yet, a random palette color so two
  /// peers rarely collide, and the platform's own light/dark preference.
  factory UserSettingsState.initial() {
    return UserSettingsState(
      name: '',
      color: kAvatarPalette[Random().nextInt(kAvatarPalette.length)],
      themeMode: ThemeMode.system,
    );
  }

  /// The name the user typed, empty until they pick one.
  final String name;

  /// The color of this peer's cursor and avatar, one of [kAvatarPalette].
  final Color color;

  /// Whether the app follows the system theme or is forced light/dark.
  final ThemeMode themeMode;

  /// [name], or [kDefaultUserName] while the user has not picked one.
  String get displayName => name.trim().isEmpty ? kDefaultUserName : name;

  /// A copy of these settings with the given fields replaced.
  UserSettingsState copyWith({
    String? name,
    Color? color,
    ThemeMode? themeMode,
  }) {
    return UserSettingsState(
      name: name ?? this.name,
      color: color ?? this.color,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  @override
  List<Object?> get props => [name, color, themeMode];
}
