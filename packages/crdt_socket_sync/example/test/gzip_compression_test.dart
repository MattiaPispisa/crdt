import 'dart:convert';

import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:crdt_socket_sync_example/src/gzip_compression.dart';
import 'package:test/test.dart';

void main() {
  const gzip = GzipCompression();

  group('GzipCompression', () {
    test('round-trips arbitrary bytes', () {
      final data = utf8.encode('the quick brown fox jumps over the lazy dog');
      expect(gzip.decompress(gzip.compress(data)), equals(data));
    });

    test('round-trips empty input', () {
      expect(gzip.decompress(gzip.compress(const [])), isEmpty);
    });

    test('round-trips every byte value (binary safe)', () {
      final data = List<int>.generate(256, (i) => i);
      expect(gzip.decompress(gzip.compress(data)), equals(data));
    });

    test('round-trips multi-byte UTF-8 / emoji losslessly', () {
      final data = utf8.encode('caffè — 日本語 — 👩‍💻🚀');
      expect(gzip.decompress(gzip.compress(data)), equals(data));
    });

    test('shrinks large repetitive input', () {
      final data = utf8.encode('ab' * 5000);
      expect(gzip.compress(data).length, lessThan(data.length));
    });
  });

  group('CompressedCodec with GzipCompression', () {
    JsonMessageCodec<Map<String, dynamic>> inner() {
      return JsonMessageCodec<Map<String, dynamic>>(
        toJson: (m) => m,
        fromJson: (json) => json,
      );
    }

    test('round-trips a message through gzip', () {
      final codec = CompressedCodec<Map<String, dynamic>>(
        inner(),
        compressor: gzip,
      );
      final message = {'items': List<int>.generate(500, (i) => i)};

      final bytes = codec.encode(message)!;
      expect(codec.decode(bytes), equals(message));
    });

    test('compresses better than NoCompression on large payloads', () {
      final message = {'text': 'lorem ipsum ' * 500};

      final gzipped =
          CompressedCodec<Map<String, dynamic>>(
            inner(),
            compressor: gzip,
          ).encode(message)!;
      final raw =
          CompressedCodec<Map<String, dynamic>>(
            inner(),
            compressor: NoCompression.instance,
          ).encode(message)!;

      expect(gzipped.length, lessThan(raw.length));
    });
  });
}
