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
  });
}
