import 'package:archive/archive.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';

/// A real [Compressor] backed by gzip (RFC 1952).
///
/// Compression is **symmetric**: if the server injects [GzipCompression], every
/// connecting client must inject the same compressor, otherwise the peer cannot
/// decode incoming messages.
class GzipCompression implements Compressor {
  /// Creates a gzip compressor.
  const GzipCompression();

  @override
  List<int> compress(List<int> data) => GZipEncoder().encode(data)!;

  @override
  List<int> decompress(List<int> data) => GZipDecoder().decodeBytes(data);
}
