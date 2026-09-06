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
        ..setWordWrap(value: false)
        ..recordRoomOpened('abc123');

      // A fresh cubit over the same storage is what a relaunch looks like.
      final restored = UserSettingsCubit(storage: storage).state;
      expect(restored.name, 'Ada');
      expect(restored.color, kAvatarPalette.last);
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.showLineNumbers, isTrue);
      expect(restored.wordWrap, isFalse);
      expect(
        restored.recentRooms.map((room) => room.roomId),
        ['abc123'],
      );
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
            'recentRooms': <Object>[
              {'roomId': 'kept', 'openedAt': 1000},
              // An id no route would accept, a timestamp that is not a
              // number, and an entry that is not a room at all.
              {'roomId': 'NOT AN ID', 'openedAt': 2000},
              {'roomId': 'later', 'openedAt': 'yesterday'},
              'garbage',
            ],
          },
        }),
      );

      expect(cubit.state.name, 'Ada');
      expect(cubit.state.color, isIn(kAvatarPalette));
      expect(cubit.state.themeMode, ThemeMode.system);
      expect(cubit.state.showLineNumbers, isFalse);
      expect(cubit.state.wordWrap, isTrue);
      expect(cubit.state.recentRooms.map((room) => room.roomId), ['kept']);
    });

    test('drops a recentRooms payload it cannot read at all', () {
      final cubit = UserSettingsCubit(
        storage: MemoryStorage({
          'UserSettings': {'recentRooms': 'abc123'},
        }),
      );

      expect(cubit.state.recentRooms, isEmpty);
    });

    test('displayName stands in for a name the user never typed', () {
      final cubit = UserSettingsCubit(storage: MemoryStorage());
      expect(cubit.state.displayName, kDefaultUserName);

      cubit.setName('  ');
      expect(cubit.state.displayName, kDefaultUserName);

      cubit.setName('Ada');
      expect(cubit.state.displayName, 'Ada');
    });

    test('recordRoomOpened lists the newest room first', () {
      final cubit = UserSettingsCubit(storage: MemoryStorage())
        ..recordRoomOpened('first')
        ..recordRoomOpened('second');

      expect(
        cubit.state.recentRooms.map((room) => room.roomId),
        ['second', 'first'],
      );
    });

    test('recordRoomOpened moves a room back to the front, once', () {
      final cubit = UserSettingsCubit(storage: MemoryStorage())
        ..recordRoomOpened('first')
        ..recordRoomOpened('second')
        ..recordRoomOpened('first');

      expect(
        cubit.state.recentRooms.map((room) => room.roomId),
        ['first', 'second'],
      );
    });

    test('recordRoomOpened keeps at most kRecentRoomsLimit rooms', () {
      final cubit = UserSettingsCubit(storage: MemoryStorage());
      for (var i = 0; i <= kRecentRoomsLimit; i++) {
        cubit.recordRoomOpened('room$i');
      }

      expect(cubit.state.recentRooms, hasLength(kRecentRoomsLimit));
      // The very first room is the one that fell off the end.
      expect(
        cubit.state.recentRooms.map((room) => room.roomId),
        isNot(contains('room0')),
      );
    });
  });
}
