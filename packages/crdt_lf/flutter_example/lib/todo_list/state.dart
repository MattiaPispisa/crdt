import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/material.dart';

class DocumentState extends ChangeNotifier {
  DocumentState._(
    this._document,
    this._handler,
    Stream<Change> networkChanges,
  ) {
    _listenToNetworkChanges(networkChanges);
  }

  factory DocumentState.create(
    PeerId author, {
    required Stream<Change> networkChanges,
  }) {
    final document = CRDTDocument(peerId: author);
    final handler = CRDTListHandler<String>(document, 'todo-list');
    return DocumentState._(document, handler, networkChanges);
  }

  final CRDTDocument _document;
  final CRDTListHandler<String> _handler;

  StreamSubscription<Change>? _networkChanges;

  void _listenToNetworkChanges(Stream<Change> networkChanges) {
    _networkChanges = networkChanges.listen((change) {
      _document.applyChange(change);
      notifyListeners();
    });
  }

  void addTodo(String todo) {
    _handler.insert(0, todo);
    notifyListeners();
  }

  void removeTodo(int index) {
    _handler.delete(index, 1);
    notifyListeners();
  }

  List<String> get todos => _handler.value;

  @override
  void dispose() {
    _networkChanges?.cancel();
    super.dispose();
  }
}
