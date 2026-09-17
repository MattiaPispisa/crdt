import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/client/incompatibility.dart';
import 'package:crdt_socket_sync/src/common/client/status.dart';
import 'package:crdt_socket_sync/src/common/client/sync_fault.dart';
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
  /// Defaults to [CRDTDocument.describeBuildCapabilities], sent as
  /// **incomplete**: an app usually opens a handler after connecting, so a kind
  /// it does not name is passed over rather than refused.
  ///
  /// One passed at construction is sent as complete, and the server also
  /// refuses on a kind left out:
  ///
  /// ```dart
  /// WebSocketClient(
  ///   document: document,
  ///   capabilities: DocumentCapabilities({
  ///     'todo-list': const HandlerFormats(
  ///       operationKinds: {0, 1, 2},
  ///       blobVersions: BlobVersionRange.single(1),
  ///     ),
  ///   }),
  /// );
  /// ```
  ///
  /// Either way, a kind that **is** named is checked in full: a missing kind,
  /// or a snapshot blob of another layout, refuses the client.
  DocumentCapabilities get capabilities =>
      _declaredCapabilities ?? document.describeBuildCapabilities();

  /// [capabilities] as the peer states them, or `null` when they claim nothing.
  ///
  /// Complete when they were passed at construction, incomplete when they come
  /// from the document; see [capabilities].
  @protected
  SyncCapabilities? get statedCapabilities {
    final stated = capabilities;
    if (stated.isEmpty) {
      return null;
    }
    return SyncCapabilities(stated, complete: _declaredCapabilities != null);
  }

  final StreamController<SyncFault> _faults =
      StreamController<SyncFault>.broadcast();

  /// What the client could not do with something the server sent.
  ///
  /// The connection is still up and the peers still understand each other;
  /// one piece of data could not be taken in. Nothing is retried, so an app
  /// that cares has to decide for itself whether to re-sync or to tell the
  /// user.
  ///
  /// Broadcast, and nothing is replayed: a fault reported before you subscribe
  /// is gone.
  Stream<SyncFault> get faults => _faults.stream;

  /// Reports [fault] on [faults].
  ///
  /// Called by the sync machinery instead of throwing: the apply runs inside
  /// the socket's read callback, where a throw reaches no `catch` and no
  /// `onError` and ends up as an uncaught error in the zone.
  void reportSyncFault(SyncFault fault) {
    if (!_faults.isClosed) {
      _faults.add(fault);
    }
  }

  /// Ends [faults]. A client calls it from its own `dispose`.
  @protected
  void closeFaults() => _faults.close();

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

  /// Acts on an [ErrorMessage] the peer sent, for the codes every client
  /// answers the same way.
  ///
  /// A terminal code refuses the build for good; anything else moves the
  /// client to [ConnectionStatus.error], and a failed handshake also frees
  /// whoever is waiting on it.
  ///
  /// A client that has codes of its own handles those first and calls this for
  /// the rest, so a terminal code added to [Protocol.terminalErrors] reaches
  /// every client without being wired up twice.
  @protected
  void handleErrorMessage(ErrorMessage message) {
    if (SyncIncompatibility.isTerminalCode(message.code)) {
      refuseBuild(code: message.code, reason: message.message);
      return;
    }

    updateConnectionStatus(ConnectionStatus.error);

    if (message.code == Protocol.errorHandshakeFailed) {
      abandonHandshake();
    }
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
