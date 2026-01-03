// ignore_for_file: avoid_print example app

import 'dart:async';

import 'package:hlc_dart/hlc_dart.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:en_logger/en_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_example/user/_state.dart';

class TodoListState extends ChangeNotifier {
  TodoListState._({
    required CRDTDocument document,
    required WebSocketClient client,
    required CRDTListHandler<Map<String, dynamic>> handler,
    required ClientAwarenessPlugin awareness,
    required EnLogger logger,
  }) : _handler = handler,
       _client = client,
       _document = document,
       _awareness = awareness,
       _logger = logger {
    _connectionStatusSubscription = _client.connectionStatus.listen((status) {
      notifyListeners();
    });

    _awareness.awarenessStream.listen((awareness) {
      notifyListeners();
    });

    // React to any document update (remote changes, snapshot imports, merges)
    _document.updates.listen((_) {
      _logger.info('document updated');
      notifyListeners();
    });
  }

  factory TodoListState.create({
    required String documentId,
    required PeerId author,
    required UserState user,
    required EnLogger logger,
  }) {
    final document = CRDTDocument(
      documentId: documentId,
      peerId: author,
      initialClock: HybridLogicalClock.now(),
    );
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
    logger.info(
      'setup client with author ${user.userId},'
      ' document id ${document.documentId}'
      ' for server ${user.url}',
    );
    return TodoListState._(
      document: document,
      client: client,
      handler: handler,
      awareness: awareness,
      logger: logger,
    );
  }

  // ignore: unused_field
  final CRDTDocument _document;
  final WebSocketClient _client;
  final CRDTListHandler<Map<String, dynamic>> _handler;
  final ClientAwarenessPlugin _awareness;
  final EnLogger _logger;
  DocumentAwareness get awareness => _awareness.awareness;

  ClientAwareness? get myAwareness => _awareness.myState;

  StreamSubscription<ConnectionStatus>? _connectionStatusSubscription;

  void connect() {
    _logger.info('connecting to server');
    _client
      ..connect()
      ..messages.listen((message) {
        _logger.info('message: $message');
      });
    _client.connectionStatus.listen((status) {
      _logger.info('connection status: $status');
      notifyListeners();
    });
  }

  ConnectionStatus get connectionStatusValue => _client.connectionStatusValue;

  void addTodo(String todo) {
    _handler.insert(_handler.length, Todo(text: todo).toJson());
    _logger.info('adding todo: $todo');
    notifyListeners();
  }

  void toggleTodo(int index) {
    final todo = _handler.value[index];
    final newTodo = Todo.fromJson(
      todo,
    ).copyWith(isDone: !Todo.fromJson(todo).isDone);
    _handler.update(index, newTodo.toJson());
    _logger.info('toggling todo: $newTodo');
    notifyListeners();
  }

  void removeTodo(int index) {
    _handler.delete(index, 1);
    _logger.info('removing todo: $index');
    notifyListeners();
  }

  void _updateAwareness({bool? isHovering, Offset? relativePosition}) {
    final nextIsHovering =
        isHovering ?? myAwareness?.metadata['isHovering'] as bool? ?? false;
    final nextRelativePositionX =
        relativePosition?.dx ??
        myAwareness?.metadata['positionX'] as double? ??
        0.0;
    final nextRelativePositionY =
        relativePosition?.dy ??
        myAwareness?.metadata['positionY'] as double? ??
        0.0;
    _awareness.updateLocalState({
      'positionX': nextRelativePositionX,
      'positionY': nextRelativePositionY,
      'isHovering': nextIsHovering,
    });
  }

  void updateCursor({required Offset relativePosition}) {
    _updateAwareness(relativePosition: relativePosition);
  }

  void setHover(bool isHovering) {
    _updateAwareness(isHovering: isHovering);
  }

  List<Todo> get todos => _handler.value.map(Todo.fromJson).toList();

  @override
  void dispose() {
    _connectionStatusSubscription?.cancel();
    _client.dispose();
    _logger.info('disposing todo list state');
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

  @override
  String toString() {
    return 'Todo(text: $text, isDone: $isDone)';
  }

  Todo copyWith({String? text, bool? isDone}) {
    return Todo(text: text ?? this.text, isDone: isDone ?? this.isDone);
  }
}
