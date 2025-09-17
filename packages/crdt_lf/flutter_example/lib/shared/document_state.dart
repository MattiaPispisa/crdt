import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:flutter/material.dart';

abstract class DocumentState extends ChangeNotifier {
  DocumentState(this._document, this._network) {
    _listenToNetworkChanges();
    _listenToLocalChanges();
  }

  final CRDTDocument _document;
  final Network _network;

  PeerId get peerId => _document.peerId;

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

  @override
  void dispose() {
    _networkChanges?.cancel();
    _localChanges?.cancel();
    super.dispose();
  }
}
