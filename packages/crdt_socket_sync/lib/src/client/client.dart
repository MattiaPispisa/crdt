import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/client/status.dart';
import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/plugins/client/client.dart';

/// Interface for the CRDT client
abstract class CRDTSocketClient {
  /// Constructor
  ///
  /// [plugins] is the list of plugins to use for the client.
  ///
  /// The plugins are used to extend the client functionality.
  CRDTSocketClient({
    List<ClientSyncPlugin>? plugins,
  }) : plugins = List.unmodifiable(plugins ?? <ClientSyncPlugin>[]) {
    for (final plugin in this.plugins) {
      plugin._client = this;
    }
  }

  /// The client plugins
  final List<ClientSyncPlugin> plugins;

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
