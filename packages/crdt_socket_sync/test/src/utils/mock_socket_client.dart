// ignore_for_file: avoid_setters_without_getters just for testing

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';

/// Mock implementation of CRDTSocketClient for testing
class MockCRDTSocketClient extends CRDTSocketClient {
  MockCRDTSocketClient({
    required this.document,
    required this.author,
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

  bool _isConnected = false;
  bool _shouldThrowOnSendMessage = false;

  @override
  Stream<ConnectionStatus> get connectionStatus =>
      _connectionStatusController.stream;

  @override
  ConnectionStatus get connectionStatusValue => _connectionStatusValue;

  @override
  Stream<Message> get messages => _messagesController.stream;

  @override
  Future<bool> connect() async {
    _isConnected = true;
    _connectionStatusController.add(ConnectionStatus.connected);
    return true;
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _connectionStatusController.add(ConnectionStatus.disconnected);
  }

  @override
  Future<void> sendMessage(Message message) async {
    if (_shouldThrowOnSendMessage) {
      throw Exception('Mock error when sending message');
    }
    _sentMessages.add(message);
  }

  @override
  Future<void> sendChange(Change change) async {
    final message = Message.change(
      documentId: document.peerId.toString(),
      change: change,
    );
    await sendMessage(message);
  }

  @override
  Future<void> requestSnapshot() async {
    final message = Message.documentStatusRequest(
      documentId: document.peerId.toString(),
      version: document.version,
    );
    await sendMessage(message);
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

  Message? getLastSentMessage() {
    return _sentMessages.isEmpty ? null : _sentMessages.last;
  }

  List<Message> getSentMessagesOfType<T extends Message>() {
    return _sentMessages.whereType<T>().toList();
  }

  bool get isConnected => _isConnected;

  void setConnectionStatus(ConnectionStatus status) {
    _connectionStatusValue = status;
    _connectionStatusController.add(_connectionStatusValue);
  }

  @override
  List<Change> get unSyncChanges => [];

  @override
  Stream<int> get unSyncChangesCount => Stream.value(0);
}
