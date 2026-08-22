import 'package:crdt_socket_sync_example/src/gzip_compression.dart';
import 'package:crdt_socket_sync_example/src/run.dart' as server;

void main(List<String> args) async {
  // Pass `--compress` to serve every message through gzip. Clients must then
  // connect with the matching compressor (see README + client_example
  // `--dart-define=USE_COMPRESSION=true`), because compression is symmetric.
  final compress = args.contains('--compress');

  await server.run(
    verbose: false,
    compressor: compress ? const GzipCompression() : null,
  );
}
