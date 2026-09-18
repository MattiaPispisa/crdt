import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/client/handshake_gate.dart';
import 'package:crdt_socket_sync/src/common/client/incompatibility.dart';
import 'package:crdt_socket_sync/src/common/client/status.dart';
import 'package:crdt_socket_sync/src/common/client/sync_fault.dart';
import 'package:crdt_socket_sync/src/common/common/common.dart';
import 'package:crdt_socket_sync/src/plugins/client/client.dart';
import 'package:meta/meta.dart';

/// Interface for the CRDT client
abstract class CRDTSocketClient {
  /// Creates a client, with [plugins] attached to it.
  ///
  /// [plugins] extend what the client does with the frames it exchanges.
  ///
  /// [capabilities] states what this build can read. One passed here is sent
  /// as **complete**, so the server also refuses a kind left out. Leave it out
  /// and it is derived from the document with
  /// [CRDTDocument.describeBuildCapabilities], sent as incomplete.
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

  /// The handshake of the current connection attempt.
  ///
  /// A transport drives it: [HandshakeGate.perform] around the opening frame,
  /// [HandshakeGate.succeed] when the peer answers. The base class resets it
  /// on its own when it gives up on the connection.
  @protected
  final HandshakeGate handshake = HandshakeGate();

  final StreamController<ConnectionStatus> _connectionStatus =
      StreamController<ConnectionStatus>.broadcast();

  ConnectionStatus _connectionStatusValue = ConnectionStatus.disconnected;

  final DocumentCapabilities? _declaredCapabilities;

  /// What this build tells the server it can read.
  ///
  /// Defaults to [CRDTDocument.describeBuildCapabilities], sent as
  /// **incomplete**: an app usually opens a handler after connecting, so a kind
  /// it does not name is passed over rather than refused. One passed at
  /// construction is sent as complete, and a kind left out refuses the client.
  ///
  /// Either way, a kind that **is** named is checked in full: a missing
  /// operation kind, or a snapshot blob of another layout, refuses the client.
  DocumentCapabilities get capabilities =>
      _declaredCapabilities ?? document.describeBuildCapabilities();

  /// [capabilities] as the peer states them, or `null` when they claim nothing.
  ///
  /// Complete when they were passed at construction, incomplete when they come
  /// from the document; see [capabilities].
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

  SyncFault? _lastFault;

  /// The last fault, or `null` while there has been none.
  ///
  /// [faults] replays nothing, so a listener attached after the fact reads
  /// this instead. Like [incompatibility] it is never cleared: it says what
  /// failed, not what is failing now.
  SyncFault? get lastFault => _lastFault;

  /// Reports [fault] on [faults] and latches it on [lastFault].
  ///
  /// {@macro sync_fault_not_thrown}
  void reportSyncFault(SyncFault fault) {
    _lastFault = fault;
    if (!_faults.isClosed) {
      _faults.add(fault);
    }
  }

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

    handshake.reset();
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
      handshake.reset();
    }
  }

  /// Moves the client to [status], and publishes it when it is a move.
  ///
  /// The same status twice is dropped. [ConnectionStatus.unsupported] is
  /// terminal: once the build has been refused, the teardown that follows
  /// (and any late frame) cannot report the client as merely disconnected.
  @protected
  void updateConnectionStatus(ConnectionStatus status) {
    if (isUnsupported && !status.isUnsupported) {
      return;
    }
    if (status == _connectionStatusValue) {
      return;
    }

    _connectionStatusValue = status;
    if (!_connectionStatus.isClosed) {
      _connectionStatus.add(status);
    }
  }

  /// Ends [faults] and [connectionStatus]. Call it from `dispose`.
  @protected
  void closeClientStreams() {
    _faults.close();
    _connectionStatus.close();
  }

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

  /// Stream of connection status changes between client and server.
  ///
  /// Broadcast, and nothing is replayed: read [connectionStatusValue] for the
  /// status a late listener missed.
  Stream<ConnectionStatus> get connectionStatus => _connectionStatus.stream;

  /// The current connection status. [ConnectionStatus.disconnected] until the
  /// first move.
  ConnectionStatus get connectionStatusValue => _connectionStatusValue;

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
