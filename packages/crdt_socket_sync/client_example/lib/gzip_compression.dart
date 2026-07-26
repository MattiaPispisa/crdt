import 'package:archive/archive.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';

/// A real [Compressor] backed by gzip (RFC 1952).
///
/// Compression is **symmetric**: the client may only inject [GzipCompression]
/// when the server it connects to compresses too, otherwise it cannot decode
/// incoming messages. See `examples.dart` (`USE_COMPRESSION`) for the toggle.
class GzipCompression implements Compressor {
  /// Creates a gzip compressor.
  const GzipCompression();

  @override
  List<int> compress(List<int> data) => GZipEncoder().encode(data)!;

  @override
  List<int> decompress(List<int> data) => GZipDecoder().decodeBytes(data);
}
