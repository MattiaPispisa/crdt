import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/plugins/common/common.dart';

/// Base class for all client plugins.
abstract class ClientSyncPlugin implements SyncPlugin {
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
