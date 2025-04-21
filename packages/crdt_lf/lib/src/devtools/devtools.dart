// coverage:ignore-file
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

/// post a [document] changed event
void postChangedEvent(CRDTDocument document) {
  if (!_enable) {
    return;
  }
  final trackedDocument = TrackedDocument._byDocument[document];
  if (trackedDocument == null) {
    return;
  }
  _postEvent('document:changed', {
    "id": trackedDocument.id,
  });
}

/// a tracked document
class TrackedDocument {
  final CRDTDocument document;
  final int id;

  /// create a new tracked document
  TrackedDocument(this.document) : id = _nextId++ {
    _byDocument[document] = this;
    all.add(this);
  }

  static int _nextId = 0;

  /// all tracked documents
  static List<TrackedDocument> all = [];

  /// map of documents to their tracked document
  static final Expando<TrackedDocument> _byDocument = Expando();
}

/// handle a [document] created event
void handleCreated(CRDTDocument document) {
  if (_enable) {
    TrackedDocument(document);
    _postCreatedEvent();
  }
}

/// describe the changes of [document]
String describeChanges(CRDTDocument document) {
  return json.encode(document.exportChanges().map((e) => e.toJson()).toList());
}
