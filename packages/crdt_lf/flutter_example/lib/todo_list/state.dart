import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:flutter/material.dart';

class DocumentState extends ChangeNotifier {
  DocumentState._(this._document, this._handler, this._network) {
    _listenToNetworkChanges();
    _listenToLocalChanges();
  }

  factory DocumentState.create(PeerId author, {required Network network}) {
    final document = CRDTDocument(peerId: author);
    final handler = CRDTListHandler<String>(document, 'todo-list');
    return DocumentState._(document, handler, network);
  }

  final CRDTDocument _document;
  final CRDTListHandler<String> _handler;
  final Network _network;

  StreamSubscription<Change>? _networkChanges;
  StreamSubscription<Change>? _localChanges;

  void _listenToNetworkChanges() {
    _networkChanges = _network
        .stream(_document.peerId)
        .listen(_applyNetworkChanges);
  }

  void _listenToLocalChanges() {
    _localChanges = _document.localChanges.listen(_sendChange);
  }

  void _applyNetworkChanges(Change change) {
    _document.applyChange(change);
    notifyListeners();
  }

  void _sendChange(Change change) {
    _network.sendChange(change);
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
    _localChanges?.cancel();
    super.dispose();
  }
}
