part of 'document.dart';

/// The deleted handlers of a document, and the rules a handler id follows
/// because of them.
///
/// The deletes live in the deletions registry, a handler under the reserved
/// id [_deletedHandlersKey] that only the document may open.
abstract class _HandlerDeletions<D extends BaseCRDTDocument> {
  _HandlerDeletions(this._document);

  final D _document;

  /// Whether this is opening the registry, the one handler allowed under the
  /// reserved id.
  bool _openingRegistry = false;

  /// Whether the handler with [handlerId] is deleted.
  bool isDeleted(String handlerId);

  /// Whether a handler may be built under a deleted id, to be read.
  bool get buildsDeleted;

  /// The deletions registry; `null` until it opens.
  CRDTORSetHandler<String>? get registry =>
      _document._registry[_deletedHandlersKey] as CRDTORSetHandler<String>?;

  /// The deletions registry, opened on first use, so a document that deletes
  /// nothing keeps the snapshots and capabilities it had before.
  CRDTORSetHandler<String> openRegistry() {
    final open = registry;
    if (open != null) {
      return open;
    }
    _openingRegistry = true;
    try {
      return _DeletionsRegistry.spec.create(_document, _deletedHandlersKey);
    } finally {
      _openingRegistry = false;
    }
  }

  /// Throws when [handler] may not open: its id is deleted, or reserved.
  void checkOpening(Handler<dynamic> handler) {
    if (isDeleted(handler.id) && !buildsDeleted) {
      throw HandlerDeletedException(handler.id);
    }
    if (isReserved(handler.id) && !_openingRegistry) {
      throw reservedIdError(handler.id);
    }
  }

  /// Whether a reference to [handlerId] resolves to nothing: the handler is
  /// deleted, or the id is reserved.
  bool hides(String handlerId) => isDeleted(handlerId) || isReserved(handlerId);

  static bool isReserved(String handlerId) => handlerId == _deletedHandlersKey;

  /// Throws for the reserved id.
  static void checkNotReserved(String handlerId) {
    if (isReserved(handlerId)) {
      throw reservedIdError(handlerId);
    }
  }

  static ArgumentError reservedIdError(String id) => ArgumentError.value(
        id,
        'id',
        'Reserved for the deleted handlers of the document',
      );
}

/// The deletes of a live document, and how a delete reaches every peer.
///
/// A delete is an add to the deletions registry. This class records them,
/// closes the deleted handlers with their subtree, and deletes the children a
/// concurrent edit added to a deleted container.
final class _LiveDeletions extends _HandlerDeletions<CRDTDocument> {
  _LiveDeletions(super._document)
      : _deletedIds = {},
        _sweptChangeCounts = {};

  /// The ids of the deleted handlers, as of the last [sync].
  final Set<String> _deletedIds;

  /// The change count of each deleted handler as [deleteLateChildren] last
  /// read it, since the last prune.
  final Map<String, int> _sweptChangeCounts;

  /// The revision of the deletions registry that [sync] last read.
  int _syncedRevision = 0;

  /// Whether this is building a deleted handler to read it.
  bool _readingDeleted = false;

  @override
  bool isDeleted(String handlerId) => _deletedIds.contains(handlerId);

  @override
  bool get buildsDeleted => _readingDeleted;

  /// Deletes [roots] and every handler reachable from them.
  void delete(Iterable<HandlerRef> roots) {
    final ids = _subtreeIds(roots)..removeWhere(isDeleted);
    if (ids.isEmpty) {
      return;
    }
    _record(ids);
    // Closed here and not by [sync]: inside an outer transaction the registry
    // does not read its own adds until the commit.
    _close(ids);
  }

  /// Opens the deletions registry when [change], just applied, is the first
  /// delete this document sees.
  void noteApplied(Change change) {
    if (registry == null && _DeletionsRegistry.isDeletionsChange(change)) {
      openRegistry();
    }
  }

  /// Forgets what [deleteLateChildren] read: a prune can lower a change count.
  void notePrune() => _sweptChangeCounts.clear();

  /// Adds [ids] to the deletions registry, in one transaction.
  void _record(Iterable<String> ids) {
    _document.runInTransaction(() {
      final registry = openRegistry();
      for (final id in ids) {
        registry.add(id);
      }
    });
  }

  /// The ids of [roots] and of every handler reachable from them.
  Set<String> _subtreeIds(Iterable<HandlerRef> roots) {
    final ids = {for (final root in roots) root.id};
    final queue = Queue<HandlerRef>.of(roots);
    while (queue.isNotEmpty) {
      final handler = _document.resolveHandler(queue.removeFirst());
      if (handler == null || handler is! ContainerHandler) {
        continue;
      }
      for (final ref in (handler as ContainerHandler).childRefs()) {
        if (ids.add(ref.id)) {
          queue.add(ref);
        }
      }
    }
    return ids;
  }

  /// Closes the handlers the deletions registry names and this document has
  /// not closed yet, with the children they hold here.
  ///
  /// A child added to a container concurrently with its delete is out of the
  /// subtree the deleting peer recorded. The peer that sees both records it,
  /// so the delete reaches it on every peer.
  void sync() {
    final registry = this.registry;
    if (registry == null) {
      return;
    }
    final revision = _document.revisionForHandler(_deletedHandlersKey);
    if (revision == _syncedRevision) {
      return;
    }
    _syncedRevision = revision;

    final recorded = registry.value;
    final roots = <HandlerRef>[];
    final reached = <String>{};
    Map<String, String>? manifest;
    for (final id in recorded) {
      if (_deletedIds.contains(id)) {
        continue;
      }
      // Read before [_close]: a deleted handler no longer resolves.
      final type = _document._registry[id]?.handlerType ??
          _typeOf(id, manifest ??= _manifest());
      if (type == null) {
        reached.add(id);
      } else {
        roots.add(HandlerRef(id, type));
      }
    }
    reached.addAll(_subtreeIds(roots));
    final unrecorded = reached.difference(recorded);
    _close(reached);
    if (unrecorded.isNotEmpty) {
      // Through the outbox: this runs while the document applies changes, and
      // a write from here would re-enter the commit in progress.
      _document._outbox.add(() {
        if (!_document._isDisposed) {
          _record(unrecorded.difference(registry.value));
        }
      });
    }
  }

  /// Opens the deletions registry when [snapshot] carries one, then [sync]s.
  void syncSnapshot(Snapshot snapshot) {
    if (snapshot.data.containsKey(_deletedHandlersKey)) {
      openRegistry();
    }
    sync();
  }

  /// Deletes the children a deleted container gained after its delete.
  ///
  /// An edit concurrent with the delete may reach this peer after it, and add
  /// a child [sync] never saw. Run it before a snapshot drops the changes that
  /// name it.
  void deleteLateChildren() {
    final children = <HandlerRef>[];
    Map<String, String>? manifest;
    for (final id in _deletedIds) {
      final count = _document.changeCountForHandler(id);
      if (count == 0 || _sweptChangeCounts[id] == count) {
        continue;
      }
      _sweptChangeCounts[id] = count;
      final type = _typeOf(id, manifest ??= _manifest());
      if (type != null) {
        children.addAll(_childRefsOfDeleted(id, type));
      }
    }
    if (children.isNotEmpty) {
      delete(children);
    }
  }

  Map<String, String> _manifest() =>
      _HandlerRegistry.manifestOf(_document._lastSnapshot);

  /// The children the deleted container with [id] references, or none when
  /// the document cannot build a [type].
  List<HandlerRef> _childRefsOfDeleted(String id, String type) {
    final spec = _document._registry.specs[type];
    if (spec == null) {
      return const [];
    }
    final Handler<dynamic> handler;
    _readingDeleted = true;
    try {
      handler = spec.create(_document, id);
    } finally {
      _readingDeleted = false;
    }
    try {
      return handler is ContainerHandler
          ? (handler as ContainerHandler).childRefs().toList()
          : const [];
    } finally {
      _document._unregisterHandler(id);
    }
  }

  /// The kind of the handler with [id], read from the snapshot [manifest] or
  /// from its changes, or `null` when the document holds neither.
  String? _typeOf(String id, Map<String, String> manifest) {
    final type = manifest[id];
    if (type != null) {
      return type;
    }
    final changes = _document.changesForHandler(id);
    if (changes.isEmpty) {
      return null;
    }
    return OperationEnvelopeCodec.decode(changes.first.payloadBytes())
        .handlerType;
  }

  /// Marks [ids] deleted and closes the handlers open under them.
  void _close(Iterable<String> ids) {
    final closed = {
      for (final id in ids)
        if (!_deletedIds.contains(id)) id,
    };
    if (closed.isEmpty) {
      return;
    }
    _document._cache.bumpDeleted(closed);
    for (final id in closed) {
      _deletedIds.add(id);
      _document._unregisterHandler(id)?._closeDeltas();
    }
    _document._undo.forget(closed);
  }
}

/// The deletes of a history view, read at its cursor.
final class _ViewDeletions extends _HandlerDeletions<_CRDTStaticProxyDocument> {
  _ViewDeletions(super._document);

  /// Whether the frozen history holds a delete at all.
  late final bool _holdsDeletions =
      (_document._lastSnapshot?.data.containsKey(_deletedHandlersKey) ??
              false) ||
          _document._frozenChanges.any(_DeletionsRegistry.isDeletionsChange);

  /// Whether the handler with [handlerId] is deleted at the cursor.
  @override
  bool isDeleted(String handlerId) {
    if (!_holdsDeletions || _HandlerDeletions.isReserved(handlerId)) {
      return false;
    }
    return openRegistry().value.contains(handlerId);
  }

  /// A view reads every handler, deleted at the cursor or not.
  @override
  bool get buildsDeleted => true;
}
