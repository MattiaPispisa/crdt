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

  static const String _eventEvent = 'crdt_lf:devtools:event';

  static const String _deltaEvent = 'crdt_lf:devtools:delta';

  static const int _maxEventIds = 20;

  static const int _maxDeltaText = 2000;

  static const int _protocol = 1;

  /// Receives every event the bridge posts, even with no VM service
  /// listener; `null` for none.
  static void Function(String kind, Map<String, Object?> data)? onEvent;

  static int _nextId = 0;

  static int _nextSession = 0;

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
          'capabilities':
              _formats(doc.describeBuildCapabilities().byHandlerType),
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
      case 'changes':
        final (tracked, doc) = _resolve(params);
        return _changes(tracked, doc, params);
      case 'operation':
        final (_, doc) = _resolve(params);
        return _operation(doc, params);
      case 'historyOpen':
        final (tracked, doc) = _resolve(params);
        return _historyOpen(tracked, doc);
      case 'historyState':
        final (tracked, _) = _resolve(params);
        return _historyState(tracked, params);
      case 'historyClose':
        final (tracked, _) = _resolve(params);
        // A stale id is a no-op: a newer `historyOpen` already ended it.
        if (_intParam(params, 'session', -1) == tracked.historyId) {
          tracked.closeHistory();
        }
        return {};
      case 'snapshot':
        final (_, doc) = _resolve(params);
        return _snapshot(doc);
      case 'eventsStart':
        final (tracked, doc) = _resolve(params);
        _eventsStart(tracked, doc);
        return {'recording': true};
      case 'eventsStop':
        final (tracked, _) = _resolve(params);
        tracked.stopEvents();
        return {'recording': false};
      case 'watchStart':
        final (tracked, doc) = _resolve(params);
        _watchStart(tracked, doc, params);
        return {'watching': true};
      case 'watchStop':
        final (tracked, _) = _resolve(params);
        final id = params['handler'];
        if (id == null) {
          throw ArgumentError.value(id, 'handler', 'Expected a handler id');
        }
        tracked.stopWatch(id);
        return {'watching': false};
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

  static void _renamed(CRDTDocument doc) {
    if (!_enabled) return;
    if (_of(doc) == null) return;
    _documentsMoved();
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

  static void _eventsStart(_Tracked tracked, CRDTDocument doc) {
    if (tracked.events != null) return;
    tracked.events = doc.events.listen((event) {
      // DevTools can close without a stop call: with no receiver left, the
      // app must stop paying for the log. The delta watch does the same.
      if (!_hasReceiver) {
        tracked.stopEvents();
        return;
      }
      _post(_eventEvent, _event(tracked, event));
    });
  }

  static Map<String, Object?> _event(
    _Tracked tracked,
    CRDTDocumentEvent event,
  ) {
    final (type, changes, origin) = switch (event) {
      DocumentChangesApplied(:final changes, :final origin) => (
          'changes',
          changes,
          origin
        ),
      DocumentSnapshotUpdated(:final origin) => (
          'snapshot',
          const <Change>[],
          origin
        ),
      DocumentHistoryPruned(:final removed, :final origin) => (
          'pruned',
          removed,
          origin
        ),
    };
    return {
      'doc': tracked.id,
      'n': tracked.eventCount++,
      'type': type,
      'source': event is DocumentChangesApplied ? event.source.name : null,
      'reason': event is DocumentSnapshotUpdated ? event.reason.name : null,
      'count': changes.length,
      'ids': [
        for (final change in changes.take(_maxEventIds)) change.id.toString(),
      ],
      'removed': event is DocumentHistoryPruned ? event.removed.length : 0,
      'rewritten': event is DocumentHistoryPruned ? event.rewritten.length : 0,
      'snapshotId': event is DocumentSnapshotUpdated ? event.snapshot.id : null,
      'origin': origin?.runtimeType.toString(),
    };
  }

  static void _watchStart(
    _Tracked tracked,
    CRDTDocument doc,
    Map<String, String> params,
  ) {
    final id = params['handler'];
    final handler = id == null ? null : doc._registry.publicView[id];
    if (id == null || handler == null) {
      throw ArgumentError.value(id, 'handler', 'Unknown handler');
    }
    if (handler is! DeltaProvider) {
      throw ArgumentError.value(id, 'handler', 'The handler has no deltas');
    }
    if (tracked.deltas.containsKey(id)) return;
    tracked.deltas[id] = (handler as DeltaProvider).watch().listen(
      (update) {
        if (!_hasReceiver) {
          tracked.stopWatch(id);
          return;
        }
        _post(_deltaEvent, _delta(tracked, id, update));
      },
      onDone: () => tracked.deltas.remove(id),
    );
  }

  static Map<String, Object?> _delta(
    _Tracked tracked,
    String handler,
    HandlerUpdate<Object?> update,
  ) {
    final delta = update is HandlerDelta<Object?> ? update : null;
    final text = delta?.delta.toString();
    return {
      'doc': tracked.id,
      'handler': handler,
      'seq': update.seq,
      'type': delta == null ? 'reset' : 'delta',
      'cause': update is HandlerReset<Object?> ? update.cause.name : null,
      'changeId': delta?.changeId.toString(),
      'author': delta?.author.toString(),
      'local': delta?.local,
      'origin': delta?.origin?.runtimeType.toString(),
      'empty': switch (delta?.delta) {
        final ComposableDelta<Object?> value => value.isEmpty,
        _ => null,
      },
      'delta': text == null || text.length <= _maxDeltaText
          ? text
          : text.substring(0, _maxDeltaText),
    };
  }

  static Map<String, Object?> _summary(_Tracked tracked, CRDTDocument doc) => {
        'id': tracked.id,
        'documentId': doc.documentId,
        'debugName': doc.debugName,
        'handlerNames': {...doc._handlerDebugNames},
        'peerId': doc.peerId.toString(),
        'hlc': doc.hlc.toString(),
        'changeCount': doc._log.changeCount,
        'handlerCount': doc._registry.publicView.length,
        'frontiers': [for (final id in doc.version) id.toString()],
        'versionVector': _versionVector(doc.getVersionVector()),
        'snapshotId': doc._lastSnapshot?.id,
        'pruneEpoch': tracked.pruneEpoch,
        'undoManagers': doc._undo.managers.length,
        'recording': tracked.events != null,
      };

  static int _intParam(
    Map<String, String> params,
    String name, [
    int? fallback,
  ]) {
    final raw = params[name];
    if (raw == null && fallback != null) return fallback;
    final value = raw == null ? null : int.tryParse(raw);
    if (value == null || value < 0) {
      throw ArgumentError.value(raw, name, 'Expected a non-negative integer');
    }
    return value;
  }

  static Map<String, String> _versionVector(VersionVector vector) => {
        for (final entry in vector.entries)
          entry.key.toString(): entry.value.toString(),
      };

  static bool _isReservedKey(String key) =>
      SnapshotRecords.reservedKeys.contains(key) ||
      _HandlerDeletions.isReserved(key);

  static Map<String, Object?> _historyOpen(
    _Tracked tracked,
    CRDTDocument doc,
  ) {
    tracked.closeHistory();
    final session = doc.toTimeTravel();
    final id = _nextSession++;
    tracked
      ..history = session
      ..historyId = id;
    return {
      'session': id,
      'length': session.length,
      'versionVector': _versionVector(doc.getVersionVector()),
      'handlers': [
        for (final entry in session._document._types.entries)
          if (!_isReservedKey(entry.key))
            {'id': entry.key, 'type': entry.value},
      ],
    };
  }

  static Map<String, Object?> _historyState(
    _Tracked tracked,
    Map<String, String> params,
  ) {
    final session = tracked.history;
    final id = _intParam(params, 'session');
    if (session == null || id != tracked.historyId) {
      throw ArgumentError.value(params['session'], 'session', 'Not open');
    }
    final cursor = _intParam(params, 'cursor');
    if (cursor > session.length) {
      throw ArgumentError.value(
        params['cursor'],
        'cursor',
        'Expected at most ${session.length}',
      );
    }
    session.jump(cursor);
    final handlerId = params['handler'];
    final handler =
        handlerId == null ? null : session.document.handlerById(handlerId);
    return {
      'cursor': session.cursor,
      'frontiers': [for (final id in session.document.version) id.toString()],
      'value': handler == null
          ? null
          : encodeDevToolsValue(
              handler.value,
              maxItems: _intParam(params, 'maxItems', 200),
              maxString: _intParam(params, 'maxString', 10000),
              maxDepth: _intParam(params, 'maxDepth', 8),
            ),
    };
  }

  static Map<String, Object?> _snapshot(CRDTDocument doc) {
    final snapshot = doc._lastSnapshot;
    return {
      'snapshot': snapshot == null ? null : _snapshotSummary(snapshot),
      'deleted': [...doc._deletions._deletedIds],
      'liveRequirements': doc._dataRequirements.isStarted
          ? _formats(doc._dataRequirements.describe().byHandlerType)
          : null,
    };
  }

  static Map<String, Object?> _snapshotSummary(Snapshot snapshot) {
    final manifest = _orNull(() => _HandlerRegistry.manifestOf(snapshot));
    final requirements = snapshot.data[SnapshotRecords.capabilitiesKey];
    return {
      'id': snapshot.id,
      'versionVector': _versionVector(snapshot.versionVector),
      'bytes': snapshot.toBytes().length,
      'entries': [
        for (final MapEntry(:key, :value) in snapshot.data.entries)
          {
            'key': key,
            'bytes': value.length,
            'reserved': _isReservedKey(key),
            'type': manifest?[key],
          },
      ],
      'unfolded': _orNull(
        () => {
          for (final id in SnapshotRecords.unfoldedEntriesOf(snapshot).keys)
            id: _orNull(
              () => SnapshotRecords.unfoldedChangesFor(snapshot, id)?.length,
            ),
        },
      ),
      'requirements': requirements == null
          ? null
          : _orNull(
              () => _formats(
                SnapshotRecords.decodeRequirements(requirements).byHandlerType,
              ),
            ),
    };
  }

  static Map<String, String> _formats(Map<String, HandlerFormats> byType) => {
        for (final entry in byType.entries) entry.key: entry.value.toString(),
      };

  // A record this build cannot read is shown as unknown, not as a failed call.
  static T? _orNull<T>(T Function() read) {
    try {
      return read();
    } on FormatException {
      return null;
    }
  }

  static Uint8List _bytesParam(Map<String, String> params, String name) {
    final raw = params[name];
    if (raw == null) {
      throw ArgumentError.value(raw, name, 'Expected base64 bytes');
    }
    try {
      return base64Decode(raw);
    } on FormatException {
      throw ArgumentError.value(raw, name, 'Expected base64 bytes');
    }
  }

  static Map<String, Object?> _changes(
    _Tracked tracked,
    CRDTDocument doc,
    Map<String, String> params,
  ) {
    final limit = _intParam(params, 'limit', 1000);
    final VersionVector since;
    if (params.containsKey('since')) {
      final bytes = _bytesParam(params, 'since');
      try {
        since = VersionVector.fromBytes(bytes);
      } on FormatException catch (e) {
        throw ArgumentError.value(params['since'], 'since', e.message);
      }
    } else {
      since = VersionVector({});
    }
    final changes = doc._log.exportChangesNewerThan(since)
      ..sort(compareChangeOrder);
    final page = changes.length > limit ? changes.sublist(0, limit) : changes;
    return {
      'pruneEpoch': tracked.pruneEpoch,
      'changeCount': doc._log.changeCount,
      'done': page.length == changes.length,
      'changes': [for (final change in page) base64Encode(change.toBytes())],
    };
  }

  static Map<String, Object?> _operation(
    CRDTDocument doc,
    Map<String, String> params,
  ) {
    final bytes = _bytesParam(params, 'change');
    final Change change;
    try {
      change = Change.fromBytes(bytes);
    } on FormatException catch (e) {
      throw ArgumentError.value(params['change'], 'change', e.message);
    }
    final result = <String, Object?>{
      'changeId': change.id.toString(),
      'handlerId': null,
      'handlerType': null,
      'kind': null,
      'stamped': null,
      'open': false,
      'payload': null,
      'error': null,
    };
    try {
      final envelope = OperationEnvelopeCodec.decode(change.payloadBytes());
      result
        ..['handlerId'] = envelope.handlerId
        ..['handlerType'] = envelope.handlerType
        ..['kind'] = envelope.kind
        ..['stamped'] = envelope.stamped;
      final handler = doc._registry.publicView[envelope.handlerId];
      if (handler == null || handler.handlerType != envelope.handlerType) {
        return result;
      }
      result
        ..['open'] = true
        ..['payload'] = encodeDevToolsValue(
          handler._operationFromChange(change)?.toPayload(),
        );
      // A broken body can throw any error, and the tool must still show the
      // change.
    } on Object catch (e) {
      result['error'] = '$e';
    }
    return result;
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
      : document = WeakReference<CRDTDocument>(document),
        deltas = <String, StreamSubscription<Object?>>{};

  final int id;

  final WeakReference<CRDTDocument> document;

  int pruneEpoch = 0;

  bool changes = false;

  bool handlers = false;

  bool snapshot = false;

  bool pruned = false;

  bool closed = false;

  StreamSubscription<CRDTDocumentEvent>? events;

  int eventCount = 0;

  final Map<String, StreamSubscription<Object?>> deltas;

  HistorySession? history;

  int? historyId;

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
    stopEvents();
    for (final subscription in deltas.values) {
      unawaited(subscription.cancel());
    }
    deltas.clear();
    closeHistory();
  }

  void stopEvents() {
    unawaited(events?.cancel());
    events = null;
  }

  void stopWatch(String handler) {
    final subscription = deltas.remove(handler);
    if (subscription != null) unawaited(subscription.cancel());
  }

  void closeHistory() {
    history?.dispose();
    history = null;
    historyId = null;
  }
}
