import 'package:crdt_socket_sync/src/common/common.dart';
import 'package:crdt_socket_sync/src/server/event.dart';

/// CRDT socket server interface
abstract class CRDTSocketServer {
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
