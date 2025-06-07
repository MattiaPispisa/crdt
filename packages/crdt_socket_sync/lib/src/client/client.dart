import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/client/status.dart';
import 'package:crdt_socket_sync/src/common/common.dart';

/// Interface for the CRDT client
abstract class CRDTSocketClient {
  /// The local CRDT document
  CRDTDocument get document;

  /// The peer ID
  PeerId get author;

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

  /// Request a snapshot from the server
  Future<void> requestSnapshot();

  /// Dispose the client
  void dispose();
}
