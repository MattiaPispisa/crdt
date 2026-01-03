import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:flutter/material.dart';

typedef EncodedTodoListType = Map<String, dynamic>;
const _kTodoListDocumentId = 'todo-list';

class DocumentState extends ChangeNotifier {
  DocumentState._(this._document, this._handler, this._network) {
    _listenToNetworkChanges();
    _listenToLocalChanges();
    _listenDoc();
  }

  factory DocumentState.create(PeerId author, {required Network network}) {
    final document = CRDTDocument(peerId: author);
    final handler = CRDTListHandler<EncodedTodoListType>(
      document,
      _kTodoListDocumentId,
    );
    return DocumentState._(document, handler, network);
  }

  final Network _network;

  final CRDTDocument _document;
  final CRDTListHandler<EncodedTodoListType> _handler;

  (HistorySession, CRDTListHandler<EncodedTodoListType>)? _historySession;

  StreamSubscription<Change>? _networkChanges;
  StreamSubscription<Change>? _localChanges;
  StreamSubscription<void>? _docChanges;

  void _listenToNetworkChanges() {
    _networkChanges = _network
        .stream(_document.peerId)
        .listen(_applyNetworkChanges);
  }

  void _listenToLocalChanges() {
    _localChanges = _document.localChanges.listen(_sendChangeToNetwork);
  }

  void _listenDoc() {
    _docChanges = _document.updates.listen(_reactToDoc);
  }

  void _applyNetworkChanges(Change change) {
    _document.applyChange(change);
    notifyListeners();
  }

  void _sendChangeToNetwork(Change change) {
    _network.sendChange(change);
  }

  void _reactToDoc(void _) {
    notifyListeners();
  }

  /// Adds a new todo item.
  void addTodo(String todo) {
    _handler.insert(0, Todo(text: todo).toJson());
  }

  /// Adds multiple todo items.
  void addTodos(List<String> todos) {
    _document.runInTransaction(() {
      for (var todo in todos.reversed) {
        _handler.insert(0, Todo(text: todo).toJson());
      }
    });
  }

  /// Removes a todo item.
  void removeTodo(int index) {
    _handler.delete(index, 1);
  }

  /// Toggles the done status of a todo item.
  void toggleTodo(int index) {
    final todo = _handler.value[index];
    final newTodo = Todo.fromJson(
      todo,
    ).copyWith(isDone: !Todo.fromJson(todo).isDone);
    _handler.update(index, newTodo.toJson());
  }

  bool canTimeTravel() {
    return _document.exportChanges().isNotEmpty;
  }

  void timeTravel() {
    final historySession = _document.toTimeTravel();
    final handler = historySession.getHandler(
      (doc) => CRDTListHandler<EncodedTodoListType>(doc, _kTodoListDocumentId),
    );
    historySession.cursorStream.listen((cursor) {
      notifyListeners();
    });
    _historySession = (historySession, handler);
    notifyListeners();
  }

  void backToLive() {
    _historySession?.$1.dispose();
    _historySession = null;
    notifyListeners();
  }

  void garbageCollection() {
    final snapshot = _document.takeSnapshot(pruneHistory: false);
    _document.garbageCollect(snapshot.versionVector);
    notifyListeners();
  }

  List<Todo> get todos {
    if (_historySession != null) {
      return _historySession!.$2.value.map(Todo.fromJson).toList();
    }
    return _handler.value.map(Todo.fromJson).toList();
  }

  bool get isTimeTraveling => _historySession != null;

  PeerId get author => _document.peerId;
  int get changesCount => _document.exportChanges().length;

  HistorySession? get historySession => _historySession?.$1;

  @override
  void dispose() {
    _networkChanges?.cancel();
    _localChanges?.cancel();
    _docChanges?.cancel();
    _historySession?.$1.dispose();
    _document.dispose();
    super.dispose();
  }
}

class Todo {
  const Todo({required this.text, this.isDone = false});

  final String text;
  final bool isDone;

  factory Todo.fromJson(EncodedTodoListType json) {
    return Todo(text: json['text'] as String, isDone: json['isDone'] as bool);
  }

  EncodedTodoListType toJson() => {'text': text, 'isDone': isDone};

  @override
  String toString() {
    return 'Todo(text: $text, isDone: $isDone)';
  }

  Todo copyWith({String? text, bool? isDone}) {
    return Todo(text: text ?? this.text, isDone: isDone ?? this.isDone);
  }
}
