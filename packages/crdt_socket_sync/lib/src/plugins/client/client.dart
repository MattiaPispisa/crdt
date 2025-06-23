import 'package:crdt_socket_sync/client.dart';

/// Base class for all client plugins.
///
/// `extends` (not ~~implements~~) this class to make the plugin work.
///
/// Once the plugin is attached to the client the `CRDTSocketClient`
/// will be available.
abstract class ClientSyncPlugin
    with SocketClientProvider
    implements SyncPlugin {
  /// Called when a message is received from the server.
  ///
  /// The plugin can then react to the message, for example by sending a
  /// response to the server.
  void onMessage(Message message);

  /// Called when the client is disconnected.
  void onDisconnected();

  /// Called when the client is connected.
  void onConnected();
}
