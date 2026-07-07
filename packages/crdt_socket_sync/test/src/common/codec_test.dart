import 'dart:convert';

import 'package:crdt_socket_sync/src/common/codec.dart';
import 'package:crdt_socket_sync/src/common/compressor.dart';
import 'package:test/test.dart';

/// Simple value type for exercising the generic codecs.
class _Payload {
  const _Payload(this.value);
  final String value;
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
  });
}
