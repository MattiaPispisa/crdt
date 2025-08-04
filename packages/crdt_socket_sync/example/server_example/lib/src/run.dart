import 'dart:async';
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:en_logger/en_logger.dart';
import 'package:server_example/src/registry.dart';
import 'package:hive/hive.dart';

const _kDefaultDbLocation = './example/db';
const _kDefaultPort = 8080;
final _kDefaultHost = InternetAddress.anyIPv4.host;
final _kDocumentPeerId = PeerId.parse('30669830-9256-4320-9ed5-f1860cd47d9f');

Future<void> run({
  int? port,
  String? host,
  List<ServerSyncPlugin>? plugins,
  CRDTServerRegistry? serverRegistry,
  bool verbose = true,
}) async {
  final logger = EnLogger(defaultPrefixFormat: PrefixFormat.snakeSquare());
  if (verbose) {
    logger.addHandler(
      PrinterHandler.custom(
        logCallback: (
          String message, {
          DateTime? time,
          int? sequenceNumber,
          int level = 0,
          String name = '',
          Zone? zone,
          Object? error,
          StackTrace? stackTrace,
        }) {
          print(message);
        },
      ),
    );
  }

  Hive.init(_kDefaultDbLocation);

  final registry =
      serverRegistry ??
      await HiveServerRegistry.init(
        logger: logger.getConfiguredInstance(prefix: 'HiveServerRegistry'),
      );
  await _setupDocument(registry);

  final server = WebSocketServer(
    serverFactory:
        () => HttpServer.bind(host ?? _kDefaultHost, port ?? _kDefaultPort),
    serverRegistry: registry,
    plugins: plugins ?? [ServerAwarenessPlugin()],
  );

  _setupSigintHandler(
    server: server,
    logger: logger.getConfiguredInstance(prefix: 'Bin'),
  );

  await _startServer(
    logger: logger.getConfiguredInstance(prefix: 'WebSocketServer'),
    server: server,
  );
}

Future<void> _setupDocument(CRDTServerRegistry registry) async {
  final documentId = _kDocumentPeerId.toString();
  if (await registry.hasDocument(documentId)) {
    return;
  }

  await registry.addDocument(documentId);
}

void _setupSigintHandler({
  required WebSocketServer server,
  required EnLogger logger,
}) {
  ProcessSignal.sigint.watch().listen((signal) async {
    logger.info('\n⏹️  Received SIGINT, shutting down gracefully...');
    await server.stop();
    logger.info('✅ Server stopped.');
    exit(0);
  });
}

Future<void> _startServer({
  required EnLogger logger,
  required WebSocketServer server,
}) async {
  try {
    server.serverEvents.listen((event) {
      logger.info('➡ Server event: $event');
    });

    await server.start();
    logger.info('✅ CRDT WebSocket Server started successfully!');
    logger.info('📡 Listening on ${server.host}:${server.port}');
    logger.info('💡 Press Ctrl+C to stop the server');

    // Keep the server running indefinitely
    logger.info('🔄 Server is running... waiting for connections');

    final completer = Completer<void>();
    await completer.future;
    return;
  } catch (e) {
    logger.error('❌ Failed to start server: $e');
    exit(1);
  }
}
