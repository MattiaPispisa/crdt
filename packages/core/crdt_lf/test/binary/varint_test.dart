import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('UVarint', () {
    test('write throws on negative value', () {
      final out = BytesBuilder(copy: false);
      expect(
        () => UVarint.write(-1, out),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('read throws when buffer is truncated mid-varint', () {
      // A single byte with continuation bit set, then EOF.
      final truncated = Uint8List.fromList([0x80]);
      expect(
        () => UVarint.read(truncated, offset: 0),
        throwsA(isA<FormatException>()),
      );
    });

    test('write/read round-trip for small and large values', () {
      for (final v in <int>[0, 1, 127, 128, 16383, 16384, 1 << 20]) {
        final out = BytesBuilder(copy: false);
        UVarint.write(v, out);
        final bytes = out.toBytes();
        final decoded = UVarint.read(bytes, offset: 0);
        expect(decoded.value, equals(v));
        expect(decoded.nextOffset, equals(bytes.length));
      }
    });

    group('length-prefixed framing', () {
      test('writeBytes/readBytes round-trip, including an empty slice', () {
        for (final payload in <List<int>>[
          <int>[],
          <int>[7],
          List<int>.generate(300, (i) => i % 256),
        ]) {
          final out = BytesBuilder(copy: false);
          UVarint.writeBytes(payload, out);
          final bytes = out.toBytes();

          final decoded = UVarint.readBytes(bytes, offset: 0, what: 'payload');
          expect(decoded.value, orderedEquals(payload));
          expect(decoded.nextOffset, equals(bytes.length));
        }
      });

      test('two fields read back in sequence', () {
        final out = BytesBuilder(copy: false);
        UVarint.writeString('type', out);
        UVarint.writeString('id-1', out);
        final bytes = out.toBytes();

        final first = UVarint.readString(bytes, offset: 0, what: 'type');
        expect(first.value, equals('type'));
        final second = UVarint.readString(
          bytes,
          offset: first.nextOffset,
          what: 'id',
        );
        expect(second.value, equals('id-1'));
        expect(second.nextOffset, equals(bytes.length));
      });

      test('a string survives the framing intact', () {
        final out = BytesBuilder(copy: false);
        // Non-BMP: the length prefix counts bytes, not code units.
        UVarint.writeString('a😀b', out);

        expect(
          UVarint.readString(out.toBytes(), offset: 0, what: 'text').value,
          equals('a😀b'),
        );
      });

      test('readBytes throws FormatException naming the truncated field', () {
        // Declares 5 bytes, supplies 2.
        final truncated = Uint8List.fromList([5, 1, 2]);
        expect(
          () => UVarint.readBytes(truncated, offset: 0, what: 'map key'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('map key'),
            ),
          ),
        );
      });
    });
  });
}
