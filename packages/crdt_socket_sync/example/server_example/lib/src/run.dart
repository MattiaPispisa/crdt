import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:en_logger/en_logger.dart';
import 'package:server_example/src/registry.dart';
import 'package:hive/hive.dart';

const _kDefaultDbLocation = './example/db';
const _kDefaultPort = 8080;
final _kDefaultHost = InternetAddress.anyIPv4.host;
final _kDocumentId = '30669830-9256-4320-9ed5-f1860cd47d9f';
final _kDocumentPeerId = PeerId.parse('97a6b8b3-fffc-4ebe-8dd4-f94e6a01c52f');

late HiveServerRegistry _registry;
late WebSocketServer _server;

Future<void> run({
  int? port,
  String? host,
  List<ServerSyncPlugin>? plugins,
  bool verbose = true,
}) async {
  // setup logger
  final logger = EnLogger(defaultPrefixFormat: PrefixFormat.snakeSquare())
    ..addHandler(
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

  // db initialization
  Hive.init(_kDefaultDbLocation);
  _registry = await HiveServerRegistry.init(
    logger: logger.getConfiguredInstance(prefix: 'HiveServerRegistry'),
  );

  await _setupDocument();

  if (verbose) {
    await _registry.showPersistence();
  }

  _server = WebSocketServer(
    serverFactory:
        () => HttpServer.bind(host ?? _kDefaultHost, port ?? _kDefaultPort),
    serverRegistry: _registry,
    plugins: plugins ?? [ServerAwarenessPlugin()],
  );
  _registry.setServer(_server);

  _setupSigintHandler(logger: logger.getConfiguredInstance(prefix: 'Bin'));

  await _startServer(
    logger: logger.getConfiguredInstance(prefix: 'WebSocketServer'),
    verbose: verbose,
  );
}

/// setup a document with id [_kDocumentId] and register a handler for the todo list.
///
/// The same handler is used across all sync examples.
Future<void> _setupDocument() async {
  final hasDocument = await _registry.hasDocument(_kDocumentId);

  if (!hasDocument) {
    await _registry.addDocument(_kDocumentId, author: _kDocumentPeerId);
  }

  final document = (await _registry.getDocument(_kDocumentId))!;
  CRDTListHandler<Map<String, dynamic>>(document, 'todo-list');
}

void _setupSigintHandler({required EnLogger logger}) {
  ProcessSignal.sigint.watch().listen((signal) async {
    logger.info('\n⏹️  Received SIGINT, shutting down gracefully...');
    await _server.stop();
    await _registry.close();
    logger.info('✅ Server stopped.');
    exit(0);
  });
}

Future<void> _startServer({
  required EnLogger logger,
  required bool verbose,
}) async {
  try {
    _server.serverEvents.listen((event) {
      if (event.type == ServerEventType.clientPingRequest && !verbose) {
        // ignore ping requests just to not spam the logs
        return;
      }

      final message = event.data?['message'] as Map<String, dynamic>?;
      if (message != null) {
        final awarenessMessage = AwarenessMessage.fromJson(message);
        if (awarenessMessage != null) {
          if (verbose) {
            logger.info('➡ Awareness message: ${awarenessMessage.toJson()}');
          }
          return;
        }
      }

      if (event.type == ServerEventType.error) {
        logger.error('❌ Server error: ${event.message}');
        return;
      }

      logger.info('➡ Server event: $event');
    });

    await _server.start();
    logger.info('✅ CRDT WebSocket Server started successfully!');
    logger.info('📡 Listening on ${_server.host}:${_server.port}');
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
