// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of '../document/document.dart';

/// The app side of the `crdt_lf` DevTools extension.
///
/// Answers the `ext.crdt_lf.devtools` service extension and posts the
/// `crdt_lf:devtools:*` events. It only reads the documents. It is off in
/// product builds.
abstract final class DevToolsBridge {
  static const bool _enabled = !bool.fromEnvironment('dart.vm.product');

  static const String _extensionName = 'ext.crdt_lf.devtools';

  static const String _documentsEvent = 'crdt_lf:devtools:documents';

  static const String _documentEvent = 'crdt_lf:devtools:document';

  static const int _protocol = 1;

  /// Receives every event the bridge posts, even with no VM service
  /// listener; `null` for none.
  static void Function(String kind, Map<String, Object?> data)? onEvent;

  static int _nextId = 0;

  static final Map<int, _Tracked> _byId = <int, _Tracked>{};

  static final Expando<_Tracked> _byDocument = Expando<_Tracked>();

  static final Finalizer<int> _finalizer = Finalizer<int>(_collected);

  static bool _registered = false;

  static bool _scheduled = false;

  static bool _documentsDirty = false;

  /// Answers the protocol [method] with [params], as the service extension
  /// does.
  ///
  /// Throws an [ArgumentError] for an unknown method, a bad parameter or an
  /// unknown document.
  static Map<String, Object?> call(
    String method,
    Map<String, String> params,
  ) {
    switch (method) {
      case 'documents':
        return {
          'protocol': _protocol,
          'documents': [
            for (final tracked in [..._byId.values])
              if (_live(tracked) case final doc?) _summary(tracked, doc),
          ],
        };
      case 'document':
        final (tracked, doc) = _resolve(params);
        return {
          ..._summary(tracked, doc),
          'undo': [for (final manager in doc._undo.managers) _undo(manager)],
          'capabilities': {
            for (final entry
                in doc.describeBuildCapabilities().byHandlerType.entries)
              entry.key: entry.value.toString(),
          },
        };
      case 'handlers':
        final (_, doc) = _resolve(params);
        return _handlers(doc);
      case 'handlerValue':
        final (_, doc) = _resolve(params);
        final id = params['handler'];
        final handler = id == null ? null : doc._registry.publicView[id];
        if (handler == null) {
          throw ArgumentError.value(id, 'handler', 'Unknown handler');
        }
        return {
          'id': handler.id,
          'type': handler.handlerType,
          'revision': doc.revisionForHandler(handler.id),
          'value': encodeDevToolsValue(
            handler.value,
            maxItems: _intParam(params, 'maxItems', 200),
            maxString: _intParam(params, 'maxString', 10000),
            maxDepth: _intParam(params, 'maxDepth', 8),
          ),
        };
    }
    throw ArgumentError.value(method, 'method', 'Unknown method');
  }

  /// Forgets every tracked document.
  ///
  /// A document created before the call stays untracked.
  static void reset() {
    for (final tracked in _byId.values) {
      _finalizer.detach(tracked);
      tracked.close();
    }
    _byId.clear();
    _documentsDirty = false;
  }

  static void _created(CRDTDocument doc) {
    if (!_enabled) return;
    // Weak, with a finalizer: a document dropped without `dispose` must not
    // stay in memory for the life of the isolate.
    final tracked = _Tracked(_nextId++, doc);
    _byId[tracked.id] = tracked;
    _byDocument[doc] = tracked;
    _finalizer.attach(doc, tracked.id, detach: tracked);
    _registerExtension();
    _documentsMoved();
  }

  static void _changed(CRDTDocument doc) {
    if (!_enabled) return;
    if (!_hasReceiver) return;
    _of(doc)?.changes = true;
    _schedule();
  }

  static void _handlersChanged(CRDTDocument doc) {
    if (!_enabled) return;
    if (!_hasReceiver) return;
    _of(doc)?.handlers = true;
    _schedule();
  }

  static void _snapshotChanged(CRDTDocument doc) {
    if (!_enabled) return;
    if (!_hasReceiver) return;
    _of(doc)?.snapshot = true;
    _schedule();
  }

  static void _pruned(CRDTDocument doc) {
    if (!_enabled) return;
    final tracked = _of(doc);
    if (tracked == null) return;
    tracked.pruneEpoch++;
    if (!_hasReceiver) return;
    tracked.pruned = true;
    _schedule();
  }

  static void _disposed(CRDTDocument doc) {
    if (!_enabled) return;
    final tracked = _of(doc);
    if (tracked == null) return;
    _finalizer.detach(tracked);
    _forget(tracked);
  }

  static void _collected(int id) {
    final tracked = _byId[id];
    if (tracked != null) {
      _forget(tracked);
    }
  }

  static void _forget(_Tracked tracked) {
    tracked.close();
    _byId.remove(tracked.id);
    _documentsMoved();
  }

  static bool get _hasReceiver =>
      onEvent != null || developer.extensionStreamHasListener;

  static _Tracked? _of(CRDTDocument doc) {
    final tracked = _byDocument[doc];
    return tracked == null || tracked.closed ? null : tracked;
  }

  static CRDTDocument? _live(_Tracked tracked) {
    final doc = tracked.document.target;
    return doc == null || doc.isDisposed ? null : doc;
  }

  static (_Tracked, CRDTDocument) _resolve(Map<String, String> params) {
    final raw = params['doc'];
    final id = raw == null ? null : int.tryParse(raw);
    if (id == null) {
      throw ArgumentError.value(raw, 'doc', 'Expected a document id');
    }
    final tracked = _byId[id];
    final doc = tracked == null ? null : _live(tracked);
    if (tracked == null || doc == null) {
      throw ArgumentError.value(raw, 'doc', 'Unknown document');
    }
    return (tracked, doc);
  }

  static void _documentsMoved() {
    if (!_hasReceiver) return;
    _documentsDirty = true;
    _schedule();
  }

  static void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    // A microtask, not a `Timer`: a pending timer fails `testWidgets`.
    scheduleMicrotask(_flush);
  }

  static void _flush() {
    _scheduled = false;
    if (_documentsDirty) {
      _documentsDirty = false;
      _post(_documentsEvent, {});
    }
    for (final tracked in [..._byId.values]) {
      if (!tracked.dirty) continue;
      final data = <String, Object?>{
        'id': tracked.id,
        'changes': tracked.changes,
        'handlers': tracked.handlers,
        'snapshot': tracked.snapshot,
        'pruned': tracked.pruned,
      };
      tracked.clearDirty();
      _post(_documentEvent, data);
    }
  }

  static void _post(String kind, Map<String, Object?> data) {
    developer.postEvent(kind, data);
    onEvent?.call(kind, data);
  }

  static void _registerExtension() {
    if (_registered) return;
    _registered = true;
    developer.registerExtension(_extensionName, (method, params) async {
      try {
        return developer.ServiceExtensionResponse.result(
          jsonEncode(call(params['method'] ?? '', params)),
        );
        // The protocol reports a bad call as an `ArgumentError`, and the VM
        // service needs it as `invalidParams`.
        // ignore: avoid_catching_errors
      } on ArgumentError catch (e) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.invalidParams,
          '$e',
        );
      } catch (e) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          '$e',
        );
      }
    });
  }

  static Map<String, Object?> _summary(_Tracked tracked, CRDTDocument doc) => {
        'id': tracked.id,
        'documentId': doc.documentId,
        'peerId': doc.peerId.toString(),
        'hlc': doc.hlc.toString(),
        'changeCount': doc._log.changeCount,
        'handlerCount': doc._registry.publicView.length,
        'frontiers': [for (final id in doc.version) id.toString()],
        'versionVector': {
          for (final entry in doc.getVersionVector().entries)
            entry.key.toString(): entry.value.toString(),
        },
        'snapshotId': doc._lastSnapshot?.id,
        'pruneEpoch': tracked.pruneEpoch,
        'undoManagers': doc._undo.managers.length,
        'recording': tracked.events != null,
      };

  static int _intParam(Map<String, String> params, String name, int fallback) {
    final raw = params[name];
    if (raw == null) return fallback;
    final value = int.tryParse(raw);
    if (value == null || value < 0) {
      throw ArgumentError.value(raw, name, 'Expected a non-negative integer');
    }
    return value;
  }

  static Map<String, Object?> _handlers(CRDTDocument doc) {
    final open = doc._registry.publicView;
    final deleted = doc._deletions._deletedIds;
    final snapshot = doc._lastSnapshot;
    final manifest = _HandlerRegistry.manifestOf(snapshot);
    final closed = <String>{
      ...SnapshotRecords.handlerIdsOf(snapshot),
      ...doc._log.handlerIds,
    }..removeWhere(
        (id) =>
            open.containsKey(id) ||
            deleted.contains(id) ||
            SnapshotRecords.reservedKeys.contains(id) ||
            _HandlerDeletions.isReserved(id),
      );
    return {
      'open': [
        for (final handler in open.values) _handlerSummary(doc, handler),
      ],
      'closed': [
        for (final id in closed)
          {
            'id': id,
            'type': manifest[id] ??
                _HandlerRegistry.typeIn(doc.changesForHandler(id)),
            'changeCount': doc.changeCountForHandler(id),
          },
      ],
      'deleted': [...deleted],
    };
  }

  static Map<String, Object?> _handlerSummary(
    CRDTDocument doc,
    Handler<dynamic> handler,
  ) {
    final id = handler.id;
    return {
      'id': id,
      'type': handler.handlerType,
      'container': handler is ContainerHandler,
      // `childRefs` reads the value: the one read `handlers` allows, so
      // only containers build their cache here.
      'children': [
        if (handler is ContainerHandler)
          for (final ref in (handler as ContainerHandler).childRefs())
            {'id': ref.id, 'type': ref.type},
      ],
      'changeCount': doc.changeCountForHandler(id),
      'revision': doc.revisionForHandler(id),
      'cache': handler._cachedState == null
          ? 'none'
          : handler._cachedEpoch != doc._cache.epoch
              ? 'stale'
              : 'warm',
      'pendingRemote': handler._pendingRemoteChanges?.length ?? 0,
      'deltas': handler is DeltaProvider,
      'watched': handler.hasDeltaListeners,
      'deltaSeq': handler._deltaHub?.seq ?? 0,
      'invertible': handler.invertible,
      'undoTracked': doc._undo.managers.any((m) => m._tracked.contains(id)),
      'snapshotBytes': handler.lastSnapshot()?.length,
    };
  }

  static Map<String, Object?> _undo(CRDTUndoManager manager) => {
        'canUndo': manager.canUndo,
        'canRedo': manager.canRedo,
        'undoDepth': manager._undoStack.length,
        'redoDepth': manager._redoStack.length,
        'tracked': [...manager._tracked],
        'stackLimit': manager.stackLimit,
        'captureTimeoutMs': manager.captureTimeout.inMilliseconds,
        'trackedOrigins': manager._trackedOrigins?.length,
      };
}

final class _Tracked {
  _Tracked(this.id, CRDTDocument document)
      : document = WeakReference<CRDTDocument>(document);

  final int id;

  final WeakReference<CRDTDocument> document;

  int pruneEpoch = 0;

  bool changes = false;

  bool handlers = false;

  bool snapshot = false;

  bool pruned = false;

  bool closed = false;

  StreamSubscription<CRDTDocumentEvent>? events;

  bool get dirty => changes || handlers || snapshot || pruned;

  void clearDirty() {
    changes = false;
    handlers = false;
    snapshot = false;
    pruned = false;
  }

  void close() {
    closed = true;
    clearDirty();
    unawaited(events?.cancel());
    events = null;
  }
}
