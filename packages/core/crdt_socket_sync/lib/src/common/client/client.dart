import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/client/incompatibility.dart';
import 'package:crdt_socket_sync/src/common/client/status.dart';
import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/plugins/client/client.dart';
import 'package:meta/meta.dart';

/// Interface for the CRDT client
abstract class CRDTSocketClient {
  /// Constructor
  ///
  /// [plugins] is the list of plugins to use for the client.
  ///
  /// The plugins are used to extend the client functionality.
  CRDTSocketClient({
    List<ClientSyncPlugin>? plugins,
    DocumentCapabilities? capabilities,
  })  : plugins = List.unmodifiable(plugins ?? <ClientSyncPlugin>[]),
        _declaredCapabilities = capabilities {
    for (final plugin in this.plugins) {
      plugin._client = this;
    }
  }

  /// The client plugins
  final List<ClientSyncPlugin> plugins;

  final DocumentCapabilities? _declaredCapabilities;

  /// What this build tells the server it can read.
  ///
  /// The server refuses a client that would receive operations it cannot
  /// decode, so an **incomplete** declaration locks a perfectly good client
  /// out. The default reads the document
  /// ([CRDTDocument.describeBuildCapabilities]), which only knows the handlers
  /// already open and the factories already registered — and the usual order
  /// is to open a handler *after* connecting.
  ///
  /// So either register the factories before [connect]:
  ///
  /// ```dart
  /// document.registerFactory('CRDTListHandler<Todo>', CRDTListHandler<Todo>.new);
  /// await client.connect();
  /// ```
  ///
  /// or state the build once, at construction, and stop depending on timing:
  ///
  /// ```dart
  /// WebSocketClient(
  ///   document: document,
  ///   capabilities: DocumentCapabilities({
  ///     'CRDTListHandler<Todo>': const HandlerCapability(
  ///       operationKinds: {0, 1, 2},
  ///       snapshotBlobVersion: 1,
  ///     ),
  ///   }),
  /// );
  /// ```
  DocumentCapabilities get capabilities =>
      _declaredCapabilities ?? document.describeBuildCapabilities();

  SyncIncompatibility? _incompatibility;

  /// Why the server refused this build, or `null` while it has not.
  ///
  /// Once it is set the client is done: [connect] gives up at once and no
  /// reconnect is scheduled, because no retry can change the answer. Show it
  /// to the user — it means the app has to be updated.
  SyncIncompatibility? get incompatibility => _incompatibility;

  /// Whether the server has refused this build.
  ///
  /// The latch behind [ConnectionStatus.unsupported]. It is never cleared: no
  /// retry can change the answer, only a newer build can.
  bool get isUnsupported => _incompatibility != null;

  /// The server refused this build: stop for good.
  ///
  /// Latches the reason, frees anyone waiting on the handshake, and closes the
  /// transport. From here [connect] and the reconnect timer are both no-ops,
  /// and the status stays [ConnectionStatus.unsupported].
  ///
  /// Called when the server answers with a terminal error code (see
  /// [SyncIncompatibility.isTerminalCode]), and when the client itself finds
  /// the server unusable — a server that speaks another protocol version has
  /// no way to say so in a frame this build understands.
  @protected
  void refuseBuild({required String code, required String reason}) {
    _incompatibility ??= SyncIncompatibility(code: code, message: reason);

    abandonHandshake();
    // Set the terminal status before tearing the transport down: the teardown
    // would otherwise report a plain disconnect, and the status is sticky from
    // here on.
    updateConnectionStatus(ConnectionStatus.unsupported);
    unawaited(disconnect());
  }

  /// Refuses a server that speaks another [Protocol.protocolVersion], and says
  /// whether it did.
  ///
  /// The server checks the client's version and can answer with an error. The
  /// other direction needs this: an **older** server never read the field and
  /// accepted the client anyway, so only the version it echoes back gives it
  /// away.
  @protected
  bool refuseServerProtocolMismatch(int serverVersion) {
    if (serverVersion == Protocol.protocolVersion) {
      return false;
    }

    refuseBuild(
      code: Protocol.errorUnsupportedProtocolVersion,
      reason: 'The server speaks protocol version $serverVersion, '
          'this client speaks ${Protocol.protocolVersion}.',
    );
    return true;
  }

  /// Frees whoever is waiting on the handshake that will never complete.
  @protected
  void abandonHandshake();

  /// Moves the client to [status].
  ///
  /// [ConnectionStatus.unsupported] is terminal: once the build has been
  /// refused, the teardown that follows (and any late frame) must not report
  /// the client as merely disconnected.
  @protected
  void updateConnectionStatus(ConnectionStatus status) {
    if (isUnsupported && !status.isUnsupported) {
      return;
    }
    publishConnectionStatus(status);
  }

  /// Hands [status] to the listeners, with no rule of its own.
  @protected
  void publishConnectionStatus(ConnectionStatus status);

  /// The local CRDT document
  CRDTDocument get document;

  /// The peer ID
  PeerId get author;

  /// The session ID
  ///
  /// [sessionId] is obtained from the server on handshake completion.
  ///
  /// If the client is not connected, [sessionId] is `null`.
  String? get sessionId;

  /// Stream of connection status changes between client and server
  Stream<ConnectionStatus> get connectionStatus;

  /// The current connection status
  ConnectionStatus get connectionStatusValue;

  /// Stream of incoming server messages
  Stream<Message> get messages;

  /// Connect the client to the server
  Future<bool> connect();

  /// Disconnect the client from the server
  Future<void> disconnect();

  /// Send a [Message] to the server
  Future<void> sendMessage(Message message);

  /// Send a [Change] to the server
  Future<void> sendChange(Change change);

  /// Request a sync message from the server
  Future<void> requestSync();

  /// Dispose the client
  void dispose();
}

/// A provider that can provide the client instance.
mixin SocketClientProvider {
  late final CRDTSocketClient _client;

  /// The client instance.
  ///
  /// This is set by the client when the plugin is initialized.
  ///
  /// Do not use this property before the plugin is attached to the client.
  CRDTSocketClient get client => _client;
}
