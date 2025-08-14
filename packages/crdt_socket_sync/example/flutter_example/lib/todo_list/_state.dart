// ignore_for_file: avoid_print example app

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_example/user/_state.dart';

class TodoListState extends ChangeNotifier {
  TodoListState._({
    required CRDTDocument document,
    required WebSocketClient client,
    required CRDTListHandler<Map<String, dynamic>> handler,
    required ClientAwarenessPlugin awareness,
  }) : _handler = handler,
       _client = client,
       _document = document,
       _awareness = awareness {
    _connectionStatusSubscription = _client.connectionStatus.listen((status) {
      notifyListeners();
    });

    _awareness.awarenessStream.listen((awareness) {
      notifyListeners();
    });
  }

  factory TodoListState.create({
    required String documentId,
    required PeerId author,
    required UserState user,
  }) {
    final document = CRDTDocument(documentId: documentId, peerId: author);
    final handler = CRDTListHandler<Map<String, dynamic>>(
      document,
      'todo-list',
    );
    final awareness = ClientAwarenessPlugin(
      throttleDuration: const Duration(milliseconds: 100),
      initialMetadata: {'username': user.username, 'surname': user.surname},
    );
    final client = WebSocketClient(
      url: user.url,
      document: document,
      author: user.userId,
      plugins: [awareness],
    );
    return TodoListState._(
      document: document,
      client: client,
      handler: handler,
      awareness: awareness,
    );
  }

  // ignore: unused_field
  final CRDTDocument _document;
  final WebSocketClient _client;
  final CRDTListHandler<Map<String, dynamic>> _handler;
  final ClientAwarenessPlugin _awareness;

  DocumentAwareness get awareness => _awareness.awareness;

  ClientAwareness? get myAwareness => _awareness.myState;

  StreamSubscription<ConnectionStatus>? _connectionStatusSubscription;

  void connect() {
    _client
      ..connect()
      ..messages.listen((message) {
        notifyListeners();
      });
    _client.connectionStatus.listen((status) {
      notifyListeners();
    });
    _client.messages.listen((message) {
      print('message: $message');
    });
  }

  ConnectionStatus get connectionStatusValue => _client.connectionStatusValue;

  void addTodo(String todo) {
    _handler.insert(_handler.length, Todo(text: todo).toJson());
    notifyListeners();
  }

  void toggleTodo(int index) {
    final todo = _handler.value[index];
    _handler.update(
      index,
      Todo.fromJson(
        todo,
      ).copyWith(isDone: !Todo.fromJson(todo).isDone).toJson(),
    );
    notifyListeners();
  }

  void removeTodo(int index) {
    _handler.delete(index, 1);
    notifyListeners();
  }

  void updateCursor(Offset position) {
    _awareness.updateLocalState({
      'positionX': position.dx,
      'positionY': position.dy,
    });
  }

  List<Todo> get todos => _handler.value.map(Todo.fromJson).toList();

  @override
  void dispose() {
    _connectionStatusSubscription?.cancel();
    _client.dispose();
    super.dispose();
  }
}

class Todo {
  const Todo({required this.text, this.isDone = false});

  final String text;
  final bool isDone;

  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(text: json['text'] as String, isDone: json['isDone'] as bool);
  }

  Map<String, dynamic> toJson() => {'text': text, 'isDone': isDone};

  Todo copyWith({String? text, bool? isDone}) {
    return Todo(text: text ?? this.text, isDone: isDone ?? this.isDone);
  }
}
