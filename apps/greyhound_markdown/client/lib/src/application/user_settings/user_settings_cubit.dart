import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import 'package:greyhound_markdown_client/src/application/room/room_id.dart';
import 'package:greyhound_markdown_client/src/application/user_settings/app_language.dart';
import 'package:greyhound_markdown_client/src/config.dart';

part 'user_settings_state.dart';

/// The user's preferences, persisted across sessions: who they are in a room
/// (name, color), how the app looks (theme mode, language) and which rooms
/// they opened last.
///
/// Restored synchronously when constructed, so the first frame already renders
/// the stored theme and language, and prefills the home screen.
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

  /// Sets the language the app is shown in.
  void setLanguage(AppLanguage language) =>
      emit(state.copyWith(language: language));

  /// Sets whether the editor draws a line-number gutter.
  void setShowLineNumbers({required bool value}) =>
      emit(state.copyWith(showLineNumbers: value));

  /// Sets whether long editor lines wrap at the pane edge.
  void setWordWrap({required bool value}) =>
      emit(state.copyWith(wordWrap: value));

  /// Puts [roomId] at the front of the recent rooms, dropping the oldest one
  /// past [kRecentRoomsLimit].
  ///
  /// Opening a room again moves it back to the front instead of listing it
  /// twice.
  void recordRoomOpened(String roomId) {
    final rooms = [
      RecentRoom(roomId: roomId, openedAt: DateTime.now().toUtc()),
      ...state.recentRooms.where((room) => room.roomId != roomId),
    ];
    emit(
      state.copyWith(
        recentRooms: rooms.take(kRecentRoomsLimit).toList(),
      ),
    );
  }

  @override
  UserSettingsState fromJson(Map<String, dynamic> json) {
    final fallback = UserSettingsState.initial();
    return UserSettingsState(
      name: json['name'] is String ? json['name'] as String : fallback.name,
      color: json['color'] is int
          ? Color(json['color'] as int)
          : fallback.color,
      themeMode: _themeModeFrom(json['themeMode']) ?? fallback.themeMode,
      language: _languageFrom(json['language']) ?? fallback.language,
      showLineNumbers: json['showLineNumbers'] is bool
          ? json['showLineNumbers'] as bool
          : fallback.showLineNumbers,
      wordWrap: json['wordWrap'] is bool
          ? json['wordWrap'] as bool
          : fallback.wordWrap,
      recentRooms: _recentRoomsFrom(json['recentRooms']),
    );
  }

  @override
  Map<String, dynamic> toJson(UserSettingsState state) => {
    'name': state.name,
    'color': state.color.toARGB32(),
    'themeMode': state.themeMode.name,
    'language': state.language.name,
    'showLineNumbers': state.showLineNumbers,
    'wordWrap': state.wordWrap,
    'recentRooms': [
      for (final room in state.recentRooms)
        {
          'roomId': room.roomId,
          'openedAt': room.openedAt.millisecondsSinceEpoch,
        },
    ],
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

/// The [AppLanguage] named [value], or `null` when it names none.
///
/// Stored by name for the same reason as the theme mode: a value written by an
/// older build must never be read as a different language.
AppLanguage? _languageFrom(Object? value) {
  for (final language in AppLanguage.values) {
    if (language.name == value) {
      return language;
    }
  }
  return null;
}

/// The recent rooms [value] holds, skipping anything it cannot read.
///
/// The limit is applied here too, so lowering [kRecentRoomsLimit] takes effect
/// on the next launch without a migration.
List<RecentRoom> _recentRoomsFrom(Object? value) {
  if (value is! List<dynamic>) {
    return const [];
  }

  final rooms = <RecentRoom>[];
  for (final Object? entry in value) {
    if (entry is! Map<String, dynamic>) {
      continue;
    }
    final Object? roomId = entry['roomId'];
    final Object? openedAt = entry['openedAt'];
    // An id this app would never have created cannot name a room: it comes
    // from a hand-edited or corrupted payload, and the route would reject it.
    if (roomId is! String || parseRoomId(roomId) == null || openedAt is! int) {
      continue;
    }
    rooms.add(
      RecentRoom(
        roomId: roomId,
        openedAt: DateTime.fromMillisecondsSinceEpoch(openedAt, isUtc: true),
      ),
    );
  }
  return rooms.take(kRecentRoomsLimit).toList();
}
