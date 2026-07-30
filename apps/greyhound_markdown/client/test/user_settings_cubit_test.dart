import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/config.dart';

import 'helpers/memory_storage.dart';

void main() {
  group('UserSettingsCubit', () {
    test('restores name, color and theme mode from the previous session', () {
      final storage = MemoryStorage();
      UserSettingsCubit(storage: storage)
        ..setName('Ada')
        ..setColor(kAvatarPalette.last)
        ..setThemeMode(ThemeMode.dark);

      // A fresh cubit over the same storage is what a relaunch looks like.
      final restored = UserSettingsCubit(storage: storage).state;
      expect(restored.name, 'Ada');
      expect(restored.color, kAvatarPalette.last);
      expect(restored.themeMode, ThemeMode.dark);
    });

    test('falls back per field on a payload it does not recognize', () {
      final cubit = UserSettingsCubit(
        storage: MemoryStorage({
          // Written by a build that stored the theme by index, and a color as
          // the string it used to be.
          'UserSettings': {'name': 'Ada', 'color': '#ff0000', 'themeMode': 1},
        }),
      );

      expect(cubit.state.name, 'Ada');
      expect(cubit.state.color, isIn(kAvatarPalette));
      expect(cubit.state.themeMode, ThemeMode.system);
    });

    test('displayName stands in for a name the user never typed', () {
      final cubit = UserSettingsCubit(storage: MemoryStorage());
      expect(cubit.state.displayName, kDefaultUserName);

      cubit.setName('  ');
      expect(cubit.state.displayName, kDefaultUserName);

      cubit.setName('Ada');
      expect(cubit.state.displayName, 'Ada');
    });
  });
}
