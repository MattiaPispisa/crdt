import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import 'package:greyhound_markdown_client/src/config.dart';

part 'user_settings_state.dart';

/// The user's preferences, persisted across sessions: who they are in a room
/// (name, color) and how the app looks (theme mode).
///
/// Restored synchronously when constructed, so the first frame already renders
/// the stored theme and prefills the home screen.
class UserSettingsCubit extends HydratedCubit<UserSettingsState> {
  /// Starts from the persisted settings, or from [UserSettingsState.initial]
  /// on a first visit.
  ///
  /// [storage] overrides the global `HydratedBloc.storage`, which tests use to
  /// stay off the real disk.
  UserSettingsCubit({Storage? storage})
    : super(UserSettingsState.initial(), storage: storage);

  /// The storage key.
  ///
  /// Pinned instead of inherited: the default is `runtimeType.toString()`,
  /// which dart2js minifies on a web release build — the key would then change
  /// from build to build and silently drop everyone's settings.
  @override
  String get storagePrefix => 'UserSettings';

  /// Sets the display name shown to the other peers of a room.
  void setName(String name) => emit(state.copyWith(name: name));

  /// Sets the color of this peer's cursor and avatar.
  void setColor(Color color) => emit(state.copyWith(color: color));

  /// Sets whether the app follows the system theme or is forced light/dark.
  void setThemeMode(ThemeMode mode) => emit(state.copyWith(themeMode: mode));

  /// Sets whether the editor draws a line-number gutter.
  void setShowLineNumbers({required bool value}) =>
      emit(state.copyWith(showLineNumbers: value));

  /// Sets whether long editor lines wrap at the pane edge.
  void setWordWrap({required bool value}) =>
      emit(state.copyWith(wordWrap: value));

  @override
  UserSettingsState fromJson(Map<String, dynamic> json) {
    final fallback = UserSettingsState.initial();
    return UserSettingsState(
      name: json['name'] is String ? json['name'] as String : fallback.name,
      color: json['color'] is int
          ? Color(json['color'] as int)
          : fallback.color,
      themeMode: _themeModeFrom(json['themeMode']) ?? fallback.themeMode,
      showLineNumbers: json['showLineNumbers'] is bool
          ? json['showLineNumbers'] as bool
          : fallback.showLineNumbers,
      wordWrap: json['wordWrap'] is bool
          ? json['wordWrap'] as bool
          : fallback.wordWrap,
    );
  }

  @override
  Map<String, dynamic> toJson(UserSettingsState state) => {
    'name': state.name,
    'color': state.color.toARGB32(),
    'themeMode': state.themeMode.name,
    'showLineNumbers': state.showLineNumbers,
    'wordWrap': state.wordWrap,
  };
}

/// The [ThemeMode] named [value], or `null` when it names none.
///
/// Stored by name rather than by index so reordering the enum upstream cannot
/// turn a stored "dark" into something else.
ThemeMode? _themeModeFrom(Object? value) {
  return switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => null,
  };
}
