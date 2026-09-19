import 'dart:convert';

import 'package:crdt_socket_sync/src/common/common/codec.dart';
import 'package:crdt_socket_sync/src/common/common/compressor.dart';
import 'package:test/test.dart';

/// Simple value type for exercising the generic codecs.
class _Payload {
  const _Payload(this.value);
  final String value;
}

/// A compressor that is not the identity, so a test can tell a frame that went
/// through it from one that did not.
///
/// Reverses the bytes behind a marker. [decompress] throws on anything without
/// the marker, the way a real one throws on bytes it did not write.
class _Reversing implements Compressor {
  const _Reversing();

  static const int _marker = 0x01;

  @override
  List<int> compress(List<int> data) => [_marker, ...data.reversed];

  @override
  List<int> decompress(List<int> data) {
    if (data.isEmpty || data.first != _marker) {
      throw const FormatException('Not compressed by this compressor');
    }
    return data.skip(1).toList().reversed.toList();
  }
}

void main() {
  JsonMessageCodec<_Payload> codec({bool encodeNull = false}) {
    return JsonMessageCodec<_Payload>(
      toJson: (p) => encodeNull ? null : {'value': p.value},
      fromJson: (json) => _Payload(json['value'] as String),
    );
  }

  group('JsonMessageCodec', () {
    test('round-trips a message', () {
      final bytes = codec().encode(const _Payload('hello'))!;
      expect(codec().decode(bytes)!.value, 'hello');
    });

    test('encode returns null when toJson returns null', () {
      expect(codec(encodeNull: true).encode(const _Payload('x')), isNull);
    });

    test('decode throws on invalid UTF-8 bytes', () {
      expect(
        () => codec().decode([0xff, 0xfe, 0x00]),
        throwsA(isA<FormatException>()),
      );
    });

    test('decode throws on non-JSON text', () {
      expect(
        () => codec().decode(utf8.encode('not json at all')),
        throwsFormatException,
      );
    });
  });

  group('NoCompression', () {
    test('compress and decompress return the data unchanged', () {
      final data = [0, 1, 2, 254, 255];
      expect(NoCompression.instance.compress(data), same(data));
      expect(NoCompression.instance.decompress(data), same(data));
    });
  });

  group('CompressedCodec', () {
    test('round-trips through identity compression', () {
      final inner = codec();
      final compressed = CompressedCodec<_Payload>(
        inner,
        compressor: NoCompression.instance,
      );

      final bytes = compressed.encode(const _Payload('world'))!;
      expect(compressed.decode(bytes)!.value, 'world');
    });

    test('encode returns null when the inner codec returns null', () {
      final compressed = CompressedCodec<_Payload>(codec(encodeNull: true));
      expect(compressed.encode(const _Payload('x')), isNull);
    });

    test('defaults to no compression when no compressor is given', () {
      final compressed = CompressedCodec<_Payload>(codec());
      // Identical bytes to the raw codec output => no compression applied.
      expect(
        compressed.encode(const _Payload('z')),
        equals(codec().encode(const _Payload('z'))),
      );
    });

    test('round-trips through a compressor that is not the identity', () {
      final compressed = CompressedCodec<_Payload>(
        codec(),
        compressor: const _Reversing(),
      );

      final bytes = compressed.encode(const _Payload('world'))!;
      expect(bytes, isNot(equals(codec().encode(const _Payload('world')))));
      expect(compressed.decode(bytes)!.value, 'world');
    });

    test('frameOf hands back what the inner codec is given', () {
      final compressed = CompressedCodec<_Payload>(
        codec(),
        compressor: const _Reversing(),
      );

      final bytes = compressed.encode(const _Payload('world'))!;
      expect(
        compressed.tryFrameOf(bytes),
        equals(codec().encode(const _Payload('world'))),
      );
    });

    test('decode refuses a frame that did not go through the compressor', () {
      // Peers have to agree on the compressor. Reading an uncompressed frame
      // as if it were fine would hide the one setup where they do not, while
      // everything this side sends back stays unreadable to the other.
      final compressed = CompressedCodec<_Payload>(
        codec(),
        compressor: const _Reversing(),
      );
      final plain = codec().encode(const _Payload('world'))!;

      expect(() => compressed.decode(plain), throwsFormatException);
    });

    test('frameOf hands back the data itself when it does not decompress', () {
      final compressed = CompressedCodec<_Payload>(
        codec(),
        compressor: const _Reversing(),
      );
      final plain = utf8.encode('never compressed');

      expect(compressed.tryFrameOf(plain), same(plain));
    });
  });
}
