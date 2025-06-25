import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/plugins/server/server.dart';
import 'package:crdt_socket_sync/src/server/event.dart';

/// CRDT socket server interface
abstract class CRDTSocketServer {
  /// Constructor
  ///
  /// [plugins] is the list of plugins to use for the server.
  ///
  /// The plugins are used to extend the server functionality.
  CRDTSocketServer({
    List<ServerSyncPlugin>? plugins,
  }) : plugins = List.unmodifiable(plugins ?? <ServerSyncPlugin>[]) {
    for (final plugin in this.plugins) {
      plugin._server = this;
    }
  }

  /// The server plugins
  final List<ServerSyncPlugin> plugins;

  /// Server events stream
  Stream<ServerEvent> get serverEvents;

  /// Start the server
  Future<bool> start();

  /// Stop the server
  Future<void> stop();

  /// Send a message to a specific client
  Future<void> sendMessageToClient(String clientId, Message message);

  /// Broadcast a message to all subscribed clients
  Future<void> broadcastMessage(
    Message message, {
    List<String>? excludeClientIds,
  });

  /// Dispose the server
  void dispose();
}

/// A provider that provide the server instance.
mixin SocketServerProvider {
  late final CRDTSocketServer _server;

  /// The server instance.
  ///
  /// This is set by the server when the plugin is attached to the server.
  ///
  /// Do not use this property before the plugin is attached to the server.
  CRDTSocketServer get server => _server;
}
