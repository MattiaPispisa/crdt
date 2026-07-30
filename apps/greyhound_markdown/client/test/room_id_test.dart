import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';

void main() {
  group('parseRoomId', () {
    test('normalizes what copy/paste adds', () {
      expect(parseRoomId('  AbC123 '), 'abc123');
      expect(parseRoomId('my-room'), 'my-room');
    });

    test('rejects what cannot name a room', () {
      for (final value in ['', '  ', 'ab', 'a b', 'room!', '-room', 'a--b']) {
        expect(parseRoomId(value), isNull, reason: value);
      }
    });
  });

  group('parseRoomRoute', () {
    test('reads the room out of a route it built', () {
      expect(parseRoomRoute(Uri.parse(roomRoute('abc123'))), 'abc123');
      // A shared link, hand-edited on the way.
      expect(parseRoomRoute(Uri.parse('/room/AbC123')), 'abc123');
    });

    test('turns down routes that name no room', () {
      for (final route in [
        '/',
        '/settings',
        '/room',
        '/room/',
        '/room/a b',
        '/room/abc/extra',
      ]) {
        expect(parseRoomRoute(Uri.parse(route)), isNull, reason: route);
      }
    });
  });

  test('generateRoomId produces ids it accepts back', () {
    final ids = List.generate(50, (_) => generateRoomId());
    for (final id in ids) {
      expect(parseRoomId(id), id);
    }
    // Drawn at random, not a constant dressed up as one.
    expect(ids.toSet().length, greaterThan(45));
  });
}
