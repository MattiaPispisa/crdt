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

  test('generateRoomId produces ids it accepts back', () {
    final ids = List.generate(50, (_) => generateRoomId());
    for (final id in ids) {
      expect(parseRoomId(id), id);
    }
    // Drawn at random, not a constant dressed up as one.
    expect(ids.toSet().length, greaterThan(45));
  });
}
