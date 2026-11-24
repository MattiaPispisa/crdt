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

  /// How long the event log, a delta watch, a time travel session or a
  /// paging of the changes lives after its last call.
  ///
  /// A start of a running log or watch renews it, and so does a
  /// `historyState` or `changes` call. The app ends the work at its next
  /// event, call or change after the lease ends.
  static Duration lease = const Duration(seconds: 30);

  static int _nextId = 0;

  static int _nextSession = 0;

  // Weak: a subscription or a session of a `_Tracked` can hold its document,
  // so only the `Expando` below, keyed by that document, keeps it.
  static final Map<int, WeakReference<_Tracked>> _byId =
      <int, WeakReference<_Tracked>>{};

  static final Expando<_Tracked> _byDocument = Expando<_Tracked>();

  // A snapshot never changes, and its size costs a whole encode.
  static final Expando<int> _snapshotBytes = Expando<int>();

  static final Finalizer<int> _finalizer = Finalizer<int>(_collected);

  // The ids of the tracked documents with a history session or a paging.
  // Ids, not `_Tracked`s: the session holds the document.
  static final Set<int> _expiring = <int>{};

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
    try {
      return _answer(method, params);
    } finally {
      // After the answer: a call on a session or a paging renews it first.
      _expireIdle();
    }
  }

  static Map<String, Object?> _answer(
    String method,
    Map<String, String> params,
  ) {
    switch (method) {
      case 'documents':
        final documents = params.containsKey('doc')
            ? [_resolve(params)]
            : [
                for (final tracked in _tracked())
                  if (_live(tracked) case final doc?) (tracked, doc),
              ];
        return {
          'protocol': _protocol,
          'documents': [
            for (final (tracked, doc) in documents) _summary(tracked, doc),
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
        final (tracked, doc) = _resolve(params);
        return _handlers(tracked, doc);
      case 'handlerValue':
        final (_, doc) = _resolve(params);
        final id = params['handler'];
        final handler = id == null ? null : doc._registry.publicView[id];
        if (handler == null) {
          throw ArgumentError.value(id, 'handler', 'Unknown handler');
        }
        final revision = doc.revisionForHandler(handler.id);
        final head = {
          'id': handler.id,
          'type': handler.handlerType,
          'revision': revision,
        };
        // An equal revision is an equal value: skip the read and the encode.
        if (params.containsKey('revision') &&
            _intParam(params, 'revision') == revision) {
          return {...head, 'unchanged': true};
        }
        return {
          ...head,
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
        return {'recording': true, 'renewed': _eventsStart(tracked, doc)};
      case 'eventsStop':
        final (tracked, _) = _resolve(params);
        tracked.stopEvents();
        return {'recording': false};
      case 'watchStart':
        final (tracked, doc) = _resolve(params);
        return {'watching': true, 'renewed': _watchStart(tracked, doc, params)};
      case 'watchStop':
        final (tracked, _) = _resolve(params);
        final id = params['handler'];
        if (id == null) {
          throw ArgumentError.value(id, 'handler', 'Expected a handler id');
        }
        _stopWatch(tracked, id);
        return {'watching': false};
    }
    throw ArgumentError.value(method, 'method', 'Unknown method');
  }

  /// What the bridge keeps in the app for [doc] on behalf of a client.
  static ({bool history, bool paging, Set<String> watched}) held(
    CRDTDocument doc,
  ) {
    final tracked = _of(doc);
    return (
      history: tracked?.history != null,
      paging: tracked?.pages != null,
      watched: {...?tracked?.deltas.keys},
    );
  }

  /// Forgets every tracked document.
  ///
  /// A document created before the call stays untracked.
  static void reset() {
    for (final tracked in _tracked()) {
      _finalizer.detach(tracked);
      tracked.close();
    }
    _byId.clear();
    _expiring.clear();
    _documentsDirty = false;
  }

  static void _created(CRDTDocument doc) {
    if (!_enabled) return;
    // Weak, with a finalizer: a document dropped without `dispose` must not
    // stay in memory for the life of the isolate.
    final tracked = _Tracked(_nextId++, doc);
    _byId[tracked.id] = WeakReference(tracked);
    _byDocument[doc] = tracked;
    _finalizer.attach(doc, tracked.id, detach: tracked);
    _registerExtension();
    _documentsMoved();
  }

  static void _changed(CRDTDocument doc) {
    if (!_enabled) return;
    // Before the receiver check: a DevTools tab closed without its close
    // call leaves no receiver.
    _expireIdle();
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
    tracked
      ..pruneEpoch += 1
      ..pages = null;
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
    _byId.remove(id)?.target?.close();
    _documentsMoved();
  }

  static void _forget(_Tracked tracked) {
    tracked.close();
    _byId.remove(tracked.id);
    _documentsMoved();
  }

  static void _expireIdle() {
    if (_expiring.isEmpty) return;
    _expiring.removeWhere((id) {
      final tracked = _byId[id]?.target;
      return tracked == null || !tracked.expireIdle();
    });
  }

  static List<_Tracked> _tracked() => [
        for (final reference in _byId.values)
          if (reference.target case final tracked?) tracked,
      ];

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
    final tracked = _byId[id]?.target;
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
    for (final tracked in _tracked()) {
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

  // Whether the log was running.
  static bool _eventsStart(_Tracked tracked, CRDTDocument doc) {
    if (tracked.events case final running?) {
      running.renew();
      return true;
    }
    late final _Lease lease;
    lease = tracked.events = _Lease(
      doc.events.listen((event) {
        if (!_hasReceiver || lease.expired) {
          tracked.stopEvents();
          return;
        }
        _post(_eventEvent, _event(tracked, event));
      }),
    );
    return false;
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

  // Whether the watch was running.
  static bool _watchStart(
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
    if (tracked.deltas[id] case final running?) {
      running.renew();
      return true;
    }
    late final _Lease lease;
    lease = tracked.deltas[id] = _Lease(
      (handler as DeltaProvider).watch().listen(
        (update) {
          if (!_hasReceiver || lease.expired) {
            _stopWatch(tracked, id);
            return;
          }
          _post(_deltaEvent, _delta(tracked, id, update));
        },
        onDone: () => tracked.deltas.remove(id),
      ),
    );
    _watchMoved(tracked);
    return false;
  }

  static void _stopWatch(_Tracked tracked, String handler) {
    if (tracked.stopWatch(handler)) _watchMoved(tracked);
  }

  // `watched` is part of the handler summary.
  static void _watchMoved(_Tracked tracked) {
    if (!_hasReceiver) return;
    tracked.handlers = true;
    _schedule();
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
          : text.substring(0, RuneOffsets.snap(text, _maxDeltaText)),
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
      ..historyId = id
      ..newestHistoryId = id
      ..historyIdle.reset();
    _expiring.add(tracked.id);
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
      throw ArgumentError.value(
        params['session'],
        'session',
        id < tracked.newestHistoryId ? 'Replaced' : 'Not open',
      );
    }
    tracked.historyIdle.reset();
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
      'bytes': _snapshotBytes[snapshot] ??= snapshot.toBytes().length,
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
          for (final MapEntry(key: id, value: entry)
              in SnapshotRecords.unfoldedEntriesOf(snapshot).entries)
            id: _orNull(() => SnapshotRecords.unfoldedCountOf(entry)),
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
    final (page, done) = _page(tracked, doc, since, limit);
    return {
      'pruneEpoch': tracked.pruneEpoch,
      'changeCount': doc._log.changeCount,
      'done': done,
      'changes': [for (final change in page) base64Encode(change.toBytes())],
    };
  }

  static (List<Change>, bool) _page(
    _Tracked tracked,
    CRDTDocument doc,
    VersionVector since,
    int limit,
  ) {
    final count = doc._log.changeCount;
    var pages = tracked.pages;
    // A prune drops the copy. Between two prunes the log only grows: the
    // copy takes in what it misses.
    if (pages != null &&
        pages.changeCount != count &&
        !pages.extend(doc._log, count)) {
      pages = tracked.pages = null;
    }
    if (pages == null) {
      final newer = doc._log.exportChangesNewerThan(since);
      if (newer.length <= limit) {
        return (newer..sort(compareChangeOrder), true);
      }
      // A caller pages through the whole log: sort it once, not per page.
      // From the empty vector, `newer` already is the whole log.
      final all = since.isEmpty ? newer : doc._log.exportChanges();
      pages = tracked.pages = _ChangePages(
        all..sort(compareChangeOrder),
        changeCount: count,
      );
      _expiring.add(tracked.id);
    }
    pages.idle.reset();
    final (page, done) = pages.after(since, limit);
    if (done) tracked.pages = null;
    return (page, done);
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

  static Map<String, Object?> _handlers(_Tracked tracked, CRDTDocument doc) {
    final open = doc._registry.publicView;
    final deleted = doc._deletions._deletedIds;
    final snapshot = doc._lastSnapshot;
    final manifest =
        _orNull(() => _HandlerRegistry.manifestOf(snapshot)) ?? const {};
    final closed = <String>{
      ...SnapshotRecords.handlerIdsOf(snapshot),
      ...doc._log.handlerIds,
    }..removeWhere(
        (id) =>
            open.containsKey(id) || deleted.contains(id) || _isReservedKey(id),
      );
    return {
      'open': [
        for (final handler in open.values) _handlerSummary(doc, handler),
      ],
      'closed': [
        for (final id in closed)
          {
            'id': id,
            'type': manifest[id] ?? tracked.typeOf(doc, id),
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
    // Before `childRefs`, which reads the value of a container.
    final cache = handler._cachedState == null
        ? 'none'
        : handler._cachedEpoch != doc._cache.epoch
            ? 'stale'
            : 'warm';
    final pendingRemote = handler._pendingRemoteChanges?.length ?? 0;
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
      'cache': cache,
      'pendingRemote': pendingRemote,
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
        deltas = <String, _Lease>{},
        historyIdle = Stopwatch()..start(),
        _types = <String, String>{};

  final int id;

  final WeakReference<CRDTDocument> document;

  int pruneEpoch = 0;

  bool changes = false;

  bool handlers = false;

  bool snapshot = false;

  bool pruned = false;

  bool closed = false;

  _Lease? events;

  int eventCount = 0;

  final Map<String, _Lease> deltas;

  HistorySession? history;

  int? historyId;

  // Ids only grow, so a client that holds an older one learns that another
  // client took the document.
  int newestHistoryId = -1;

  final Stopwatch historyIdle;

  _ChangePages? pages;

  // A handler id keeps its type, and reading it copies the handler's changes.
  final Map<String, String> _types;

  /// The type the changes of the handler [id] name; `null` for none.
  String? typeOf(CRDTDocument doc, String id) {
    if (_types[id] case final type?) return type;
    final type = _HandlerRegistry.typeIn(doc.changesForHandler(id));
    if (type != null) _types[id] = type;
    return type;
  }

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
    for (final lease in deltas.values) {
      lease.cancel();
    }
    deltas.clear();
    closeHistory();
    pages = null;
  }

  /// Ends the history session and the paging idle for a whole lease, and
  /// tells whether one of them is still open.
  bool expireIdle() {
    if (history != null && historyIdle.elapsed >= DevToolsBridge.lease) {
      closeHistory();
    }
    if (pages case final pages?
        when pages.idle.elapsed >= DevToolsBridge.lease) {
      this.pages = null;
    }
    return history != null || pages != null;
  }

  void stopEvents() {
    events?.cancel();
    events = null;
  }

  bool stopWatch(String handler) {
    final lease = deltas.remove(handler);
    lease?.cancel();
    return lease != null;
  }

  void closeHistory() {
    history?.dispose();
    history = null;
    historyId = null;
  }
}

// DevTools can close without a stop call, and an IDE listening to the VM
// keeps `_hasReceiver` true: a lease the tool must renew ends the work.
final class _Lease {
  _Lease(this._subscription) : _since = Stopwatch()..start();

  final StreamSubscription<Object?> _subscription;

  final Stopwatch _since;

  bool get expired => _since.elapsed >= DevToolsBridge.lease;

  void renew() => _since.reset();

  void cancel() => unawaited(_subscription.cancel());
}

final class _ChangePages {
  _ChangePages(this._sorted, {required this.changeCount})
      : _positions = <PeerId, List<int>>{},
        _latest = VersionVector({}),
        idle = Stopwatch()..start() {
    _index(0);
  }

  final List<Change> _sorted;

  // The indexes of the changes of each peer in `_sorted`, in order.
  final Map<PeerId, List<int>> _positions;

  final VersionVector _latest;

  int changeCount;

  final Stopwatch idle;

  void _index(int from) {
    for (final positions in _positions.values) {
      positions.length = positions.lowerBoundBy(from, (p, f) => p - f);
    }
    for (var i = from; i < _sorted.length; i++) {
      final change = _sorted[i];
      (_positions[change.id.peerId] ??= <int>[]).add(i);
      _latest.update(change.id.peerId, change.hlc);
    }
  }

  /// Takes in the changes [log] got since; `false` when they do not add up
  /// to [count].
  bool extend(ChangeLog log, int count) {
    // A peer's changes reach the log in causal order, so the new ones are
    // newer than `_latest`.
    final added = log.exportChangesNewerThan(_latest)..sort(compareChangeOrder);
    if (_sorted.length + added.length != count) return false;
    changeCount = count;
    if (added.isEmpty) return true;
    final int from;
    if (_sorted.isEmpty || compareChangeOrder(_sorted.last, added.first) < 0) {
      from = _sorted.length;
      _sorted.addAll(added);
    } else {
      from = _merge(added);
    }
    _index(from);
    return true;
  }

  // Merges [added] into the copy and returns the first index it moved.
  int _merge(List<Change> added) {
    final first = _sorted.lowerBoundBy(added.first, compareChangeOrder);
    final tail = _sorted.sublist(first);
    _sorted.length = first;
    var i = 0;
    var j = 0;
    while (i < tail.length && j < added.length) {
      _sorted.add(
        compareChangeOrder(tail[i], added[j]) < 0 ? tail[i++] : added[j++],
      );
    }
    _sorted
      ..addAll(tail.skip(i))
      ..addAll(added.skip(j));
    return first;
  }

  (List<Change>, bool) after(VersionVector since, int limit) {
    // The page starts at the first change some peer still has to send: a
    // peer that stopped writing early must not hold every page back.
    var start = _sorted.length;
    for (final MapEntry(key: peer, value: positions) in _positions.entries) {
      final clock = since[peer];
      final next = clock == null
          ? 0
          : positions.lowerBoundBy(
              clock,
              (at, t) => _sorted[at].hlc <= t ? -1 : 1,
            );
      if (next < positions.length && positions[next] < start) {
        start = positions[next];
      }
    }
    final page = <Change>[];
    for (var i = start; i < _sorted.length; i++) {
      final change = _sorted[i];
      final clock = since[change.id.peerId];
      if (clock != null && change.hlc <= clock) continue;
      if (page.length == limit) return (page, false);
      page.add(change);
    }
    return (page, true);
  }
}
