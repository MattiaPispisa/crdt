import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/config.dart';

import 'helpers/memory_storage.dart';

void main() {
  group('UserSettingsCubit', () {
    test('restores every setting from the previous session', () {
      final storage = MemoryStorage();
      UserSettingsCubit(storage: storage)
        ..setName('Ada')
        ..setColor(kAvatarPalette.last)
        ..setThemeMode(ThemeMode.dark)
        ..setShowLineNumbers(value: true)
        ..setWordWrap(value: false);

      // A fresh cubit over the same storage is what a relaunch looks like.
      final restored = UserSettingsCubit(storage: storage).state;
      expect(restored.name, 'Ada');
      expect(restored.color, kAvatarPalette.last);
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.showLineNumbers, isTrue);
      expect(restored.wordWrap, isFalse);
    });

    test('falls back per field on a payload it does not recognize', () {
      final cubit = UserSettingsCubit(
        storage: MemoryStorage({
          // Written by a build that stored the theme by index, a color as the
          // string it used to be, and knew nothing of the editor options.
          'UserSettings': {
            'name': 'Ada',
            'color': '#ff0000',
            'themeMode': 1,
            'wordWrap': 'yes',
          },
        }),
      );

      expect(cubit.state.name, 'Ada');
      expect(cubit.state.color, isIn(kAvatarPalette));
      expect(cubit.state.themeMode, ThemeMode.system);
      expect(cubit.state.showLineNumbers, isFalse);
      expect(cubit.state.wordWrap, isTrue);
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
