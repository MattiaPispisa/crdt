import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

Uint8List _framedWithVersion(int version, List<Uint8List> blobs) {
  final encoded = ChangeCodec.encodeBlobs(blobs);
  return Uint8List.fromList(encoded)..[6] = version;
}

void main() {
  group('ChangeCodec', () {
    test('round-trips the blobs it framed', () {
      final blobs = [
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([]),
        Uint8List.fromList([9]),
      ];

      final decoded = ChangeCodec.decodeBlobs(ChangeCodec.encodeBlobs(blobs));

      expect(decoded.length, equals(3));
      expect(decoded[0], equals([1, 2, 3]));
      expect(decoded[1], isEmpty);
      expect(decoded[2], equals([9]));
    });

    // 3.x framed a change without the byte `Change.toBytes` leads with, so a
    // v1 blob and a v2 blob are different things under the same magic.
    test('refuses the framing version 3.x wrote', () {
      final framed = _framedWithVersion(1, [
        Uint8List.fromList([1, 2, 3]),
      ]);

      expect(
        () => ChangeCodec.decodeBlobs(framed),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('1'), contains('${ChangeCodec.version}')),
          ),
        ),
      );
    });

    test('refuses bad magic before it looks at the version', () {
      final blobs = [
        Uint8List.fromList([1]),
      ];
      final framed = Uint8List.fromList(ChangeCodec.encodeBlobs(blobs))
        ..[0] = 0;

      expect(
        () => ChangeCodec.decodeBlobs(framed),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('magic'),
          ),
        ),
      );
    });
  });
}
