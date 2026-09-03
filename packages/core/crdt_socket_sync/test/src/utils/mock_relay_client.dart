// ignore_for_file: avoid_setters_without_getters just for testing

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/relay_client.dart';

/// Mock implementation of [RelaySocketClient] for testing
class MockRelaySocketClient extends RelaySocketClient {
  MockRelaySocketClient({
    required this.document,
    required this.author,
    super.plugins,
  });

  @override
  final CRDTDocument document;

  @override
  String? get sessionId => 'test-session-id';

  @override
  final PeerId author;

  final List<Message> _sentMessages = [];

  List<Message> get sentMessages => List.from(_sentMessages);

  ConnectionStatus _connectionStatusValue = ConnectionStatus.disconnected;

  final StreamController<ConnectionStatus> _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();
  final StreamController<Message> _messagesController =
      StreamController<Message>.broadcast();

  bool _shouldThrowOnSendMessage = false;

  @override
  int get pendingChangesCount => 0;

  @override
  int get lastKnownSeq => 0;

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;

  @override
  ConnectionStatus get connectionStatusValue => _connectionStatusValue;

  @override
  Stream<Message> get messages => _messagesController.stream;

  @override
  Future<bool> connect() async {
    setConnectionStatus(ConnectionStatus.connected);
    return true;
  }

  @override
  Future<void> disconnect() async {
    setConnectionStatus(ConnectionStatus.disconnected);
  }

  @override
  Future<void> sendMessage(Message message) async {
    if (_shouldThrowOnSendMessage) {
      throw Exception('Mock error when sending message');
    }
    _sentMessages.add(message);
  }

  @override
  Future<void> sendChange(Change change) async {}

  @override
  Future<void> requestSync() async {
    await sendMessage(
      RelayStateRequestMessage(documentId: document.documentId),
    );
  }

  @override
  void dispose() {
    _connectionStatusController.close();
    _messagesController.close();
  }

  // Test helper methods
  set setShouldThrowOnSendMessage(bool shouldThrow) {
    _shouldThrowOnSendMessage = shouldThrow;
  }

  void clearSentMessages() {
    _sentMessages.clear();
  }

  List<T> getSentMessagesOfType<T extends Message>() {
    return _sentMessages.whereType<T>().toList();
  }

  void setConnectionStatus(ConnectionStatus status) {
    _connectionStatusValue = status;
    _connectionStatusController.add(_connectionStatusValue);
  }
}
