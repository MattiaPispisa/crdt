import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crdt_lf/src/document.dart';

const _releaseMode = bool.fromEnvironment('dart.vm.product');

const _enable = !_releaseMode;

void _postEvent(String type, Map<Object?, Object?> data) {
  developer.postEvent('crdt_lf:$type', data);
}

void _postCreatedEvent() {
  _postEvent('documents:created', {});
}

void postChangedEvent() {
  _postEvent('document:changed', {});
}

class TrackedDocument {
  final CRDTDocument document;
  final int id;

  TrackedDocument(this.document) : id = _nextId++ {
    _byDocument[document] = this;
    all.add(this);
  }

  static int _nextId = 0;

  static List<TrackedDocument> all = [];
  static final Expando<TrackedDocument> _byDocument = Expando();
}

void handleCreated(CRDTDocument document) {
  if (_enable) {
    TrackedDocument(document);
    _postCreatedEvent();
  }
}

String describeChanges(CRDTDocument document) {
  return json.encode(document.exportChanges().map((e) => e.toJson()).toList());
}
