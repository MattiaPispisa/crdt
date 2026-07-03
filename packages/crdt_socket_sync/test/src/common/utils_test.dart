import 'dart:convert';

import 'package:crdt_socket_sync/src/common/utils.dart';
import 'package:test/test.dart';

void main() {
  group('frameToBytes', () {
    test('passes through binary frames unchanged', () {
      final bytes = [1, 2, 3, 255, 0];
      expect(frameToBytes(bytes), same(bytes));
    });

    test('decodes ASCII text frames with utf8', () {
      expect(frameToBytes('hello'), utf8.encode('hello'));
    });

    test('decodes multi-byte / non-ASCII text frames with utf8', () {
      // Regression for the `codeUnits` bug: `codeUnits` returns UTF-16 units,
      // which differ from the UTF-8 bytes the server encodes with. A round
      // trip must reproduce the exact bytes the peer produced.
      const text = 'caffè — 🚀 déjà vu';
      expect(frameToBytes(text), utf8.encode(text));
      // And it must NOT match the buggy codeUnits path.
      expect(frameToBytes(text), isNot(equals(text.codeUnits)));
    });

    test('throws on unsupported frame types', () {
      expect(() => frameToBytes(42), throwsFormatException);
      expect(() => frameToBytes(null), throwsFormatException);
    });
  });

  group('tryCatchIgnore', () {
    test('runs the function on the happy path', () async {
      var ran = false;
      await tryCatchIgnore(() async {
        ran = true;
      });
      expect(ran, isTrue);
    });

    test('swallows synchronous and asynchronous errors', () async {
      await expectLater(
        tryCatchIgnore(() => throw Exception('sync')),
        completes,
      );
      await expectLater(
        tryCatchIgnore(() async => throw Exception('async')),
        completes,
      );
    });
  });
}
