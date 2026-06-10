import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crdt_lf/src/change/change.dart';
import 'package:crdt_lf/src/document.dart';

const _packageName = 'crdt_lf';

const _releaseMode = bool.fromEnvironment('dart.vm.product');

const _enable = !_releaseMode;

void _postEvent(String type, Map<Object?, Object?> data) {
  developer.postEvent('$_packageName:$type', data);
}

void _postCreatedEvent() {
  _postEvent('documents:created', {});
}

/// Post a [document] changed event.
///
/// Carries the tracked document id so listeners can match without reloading
/// the full document list.
void postChangedEvent(CRDTDocument document) {
  if (!_enable) {
    return;
  }
  final trackedDocument = TrackedDocument._byDocument[document];
  if (trackedDocument == null) {
    return;
  }
  _postEvent('document:changed', {
    'id': trackedDocument.id,
  });
}

/// A document being observed by devtools.
class TrackedDocument {
  /// Create a new tracked document.
  TrackedDocument(this.document) : id = _nextId++ {
    _byDocument[document] = this;
    all.add(this);
  }

  /// The document being tracked.
  final CRDTDocument document;

  /// A devtools-local numeric identifier (independent of the CRDT documentId).
  final int id;

  static int _nextId = 0;

  /// All tracked documents.
  static List<TrackedDocument> all = [];

  /// Map of documents to their tracked document.
  static final Expando<TrackedDocument> _byDocument = Expando();

  static TrackedDocument? _findById(int id) {
    for (final t in all) {
      if (t.id == id) {
        return t;
      }
    }
    return null;
  }
}

/// Handle a document creation event.
///
/// Registers the document with the devtools tracker and emits a
/// `crdt_lf:documents:created` event.
void handleCreated(CRDTDocument document) {
  if (_enable) {
    TrackedDocument(document);
    _postCreatedEvent();
  }
}

/// JSON list of tracked documents with lightweight metadata.
///
/// Shape (per element):
/// ```json
/// {
///   "id": 0,
///   "documentId": "<uuid-or-string>",
///   "peerId": "<uuid>",
///   "changesCount": 42,
///   "handlersCount": 3,
///   "version": ["peer@hlc", ...]
/// }
/// ```
String describeDocumentsJson() {
  final list = TrackedDocument.all.map(_documentSummary).toList();
  return jsonEncode(list);
}

/// JSON describing a single document, including handler list.
///
/// Returns `null`-shaped error JSON `{"error": "..."}` if the document is not
/// tracked.
String describeDocumentJson(int trackedId) {
  final tracked = TrackedDocument._findById(trackedId);
  if (tracked == null) {
    return jsonEncode({'error': 'Unknown trackedId: $trackedId'});
  }
  final summary = _documentSummary(tracked);
  final handlers = tracked.document.registeredHandlers.entries
      .map(
        (entry) => {
          'id': entry.key,
          'type': entry.value.runtimeType.toString(),
          'value': entry.value.toString(),
        },
      )
      .toList();
  return jsonEncode({
    ...summary,
    'handlers': handlers,
  });
}

/// JSON list of changes for a document.
///
/// Shape (per element):
/// ```json
/// {
///   "id": "peer@hlc",
///   "hlc": "l.c",
///   "author": "<peerId>",
///   "deps": ["peer@hlc", ...],
///   "payloadSize": 24,
///   "bytes": "<base64 of Change.toBytes()>"
/// }
/// ```
String describeChangesJson(int trackedId) {
  final tracked = TrackedDocument._findById(trackedId);
  if (tracked == null) {
    return jsonEncode({'error': 'Unknown trackedId: $trackedId'});
  }
  final changes = tracked.document.exportChanges()
    ..sort((a, b) => a.hlc.compareTo(b.hlc));
  final list = changes.map(_changeDescriptor).toList();
  return jsonEncode(list);
}

/// JSON describing the document history timeline.
///
/// Shape:
/// ```json
/// {
///   "length": 7,
///   "changes": [
///     {"id": "...", "hlc": "...", ...},
///     ...
///   ]
/// }
/// ```
///
/// The returned `changes` list is ordered by HLC, matching the order in which
/// they were applied. The history cursor is managed entirely on the extension
/// side — this endpoint just provides the timeline.
String describeHistoryJson(int trackedId) {
  final tracked = TrackedDocument._findById(trackedId);
  if (tracked == null) {
    return jsonEncode({'error': 'Unknown trackedId: $trackedId'});
  }
  final changes = tracked.document.exportChanges()
    ..sort((a, b) => a.hlc.compareTo(b.hlc));
  return jsonEncode({
    'length': changes.length,
    'changes': changes.map(_changeDescriptor).toList(),
  });
}

/// Short debug description of a document's changes
/// (count + binary export size).
String describeChanges(CRDTDocument document) {
  final changes = document.exportChanges();
  final v2 = document.binaryExportChanges();
  return '${changes.length} changes, ${v2.length} bytes (v2)';
}

Map<String, Object?> _documentSummary(TrackedDocument tracked) {
  final doc = tracked.document;
  return {
    'id': tracked.id,
    'documentId': doc.documentId,
    'peerId': doc.peerId.toString(),
    'changesCount': doc.exportChanges().length,
    'handlersCount': doc.registeredHandlers.length,
    'version': doc.version.map((id) => id.toString()).toList(),
  };
}

Map<String, Object?> _changeDescriptor(Change change) {
  return {
    'id': change.id.toString(),
    'hlc': change.hlc.toString(),
    'author': change.author.toString(),
    'deps': change.deps.map((d) => d.toString()).toList(),
    'payloadSize': change.payloadBytes().length,
    'bytes': base64Encode(change.toBytes()),
  };
}
