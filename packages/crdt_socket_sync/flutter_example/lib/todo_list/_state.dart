import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:flutter/material.dart';

class TodoListState extends ChangeNotifier {
  TodoListState._({
    required CRDTDocument document,
    required WebSocketClient client,
    required CRDTListHandler<String> handler,
  }) : _handler = handler,
       _client = client,
       _document = document {
    _connectionStatusSubscription = _client.connectionStatus.listen((status) {
      notifyListeners();
    });
  }

  factory TodoListState.create({
    required PeerId documentId,
    required PeerId userId,
  }) {
    final document = CRDTDocument(peerId: documentId);
    final handler = CRDTListHandler<String>(document, 'todo-list');
    final client = WebSocketClient(
      url: 'ws://192.168.1.37:8080',
      document: document,
      author: userId,
    );
    return TodoListState._(
      document: document,
      client: client,
      handler: handler,
    );
  }

  // ignore: unused_field
  final CRDTDocument _document;
  final WebSocketClient _client;
  final CRDTListHandler<String> _handler;

  StreamSubscription<ConnectionStatus>? _connectionStatusSubscription;

  void connect() {
    _client
      ..connect()
      ..messages.listen((message) {
        notifyListeners();
      });

    _client.messages.listen((message) {
      print('message: $message');
    });
  }

  ConnectionStatus get connectionStatusValue => _client.connectionStatusValue;

  void addTodo(String todo) {
    _handler.insert(_handler.length, todo);
    notifyListeners();
  }

  void removeTodo(int index) {
    _handler.delete(index, 1);
    notifyListeners();
  }

  List<String> get todos => _handler.value;

  @override
  void dispose() {
    _connectionStatusSubscription?.cancel();
    _client.dispose();
    super.dispose();
  }
}
