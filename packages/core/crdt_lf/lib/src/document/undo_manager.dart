part of 'document.dart';

/// What a [CRDTUndoManager] is doing, which is what decides where the
/// inverses it captures are pushed.
enum _UndoMode {
  /// Ordinary editing: inverses go on the undo stack.
  recording,

  /// An [CRDTUndoManager.undo] is running: inverses go on the redo stack.
  undoing,

  /// An [CRDTUndoManager.redo] is running: inverses go on the undo stack.
  redoing,
}

/// One step of a [CRDTUndoManager]'s history.
///
/// It holds the inverses of the operations of one step, in the order those
/// operations were written. Undoing the step applies them backwards.
class _UndoEntry {
  _UndoEntry(this.origin);

  /// What the writes of this step were tagged with; `null` when untagged.
  final Object? origin;

  /// The inverses, one group per operation undone, in the order those
  /// operations were written.
  ///
  /// A group is written in order — an operation may need more than one to be
  /// taken back, and they can depend on each other. The groups are written
  /// backwards.
  final List<List<Operation>> groups = <List<Operation>>[];

  /// When this step was closed, in milliseconds since the epoch.
  int closedAt = 0;
}

/// Undo and redo for the local edits of a [CRDTDocument].
///
/// ## What an undo is here
///
/// A change is immutable, it is already in the DAG, and it may already have
/// reached other peers, so an undo never removes one. It **writes a new
/// operation that has the opposite effect**, built by the handler that owns the
/// original (see [Handler.invert]).
///
/// That inverse names CRDT identities — element ids, keys, tags — never a
/// position. So an undo stays right even when other peers edited the same
/// handler in between: it takes back exactly what this peer did, and leaves
/// their work alone.
///
/// ## Using it
///
/// ```dart
/// final document = CRDTDocument();
/// final text = CRDTFugueTextHandler(document, 'text');
/// final undo = CRDTUndoManager(document)..track(text);
///
/// text.insert(0, 'Hello');
/// undo.undo(); // text.value == ''
/// undo.redo(); // text.value == 'Hello'
/// ```
///
/// A handler has to be [track]ed to be undoable, and it has to be able to
/// invert its own operations ([Handler.invertible]).
///
/// ## What is one step
///
/// A [CRDTDocument.runInTransaction] is one step, whatever the number of
/// operations inside it. Outside a transaction each write is its own step, and
/// steps written close to each other are merged: see [captureTimeout]. Call
/// [stopCapturing] to end a step by hand.
///
/// ## What it does not undo
///
/// - **Remote changes.** Only what this peer writes is captured, and only
///   through [BaseCRDTDocument.registerOperation]; an operation handed to
///   [CRDTDocument.createChange] never reaches the stack.
/// - **Snapshots.** [CRDTDocument.importSnapshot] and
///   [CRDTDocument.mergeSnapshot] replace the base the state is replayed from,
///   so both stacks are dropped.
/// - **Anything older than a prune.** [CRDTDocument.garbageCollect], and
///   [CRDTDocument.takeSnapshot] unless you pass `pruneHistory: false`, leave
///   the state to be read from the snapshot. A snapshot carries less identity
///   than the changes it replaces so both stacks are dropped there too.
/// - **A register back to empty.** A register has no operation that clears it,
///   and it cannot tell a stored `null` from one that was never written, so an
///   undo reaches neither.
/// - **The contents of a nested handler.** Undoing a write that stored a
///   [HandlerRef] removes the reference; the data of the handler it pointed at
///   stays where it is.
class CRDTUndoManager {
  /// Creates a manager over [document] that tracks nothing yet.
  ///
  /// [trackedOrigins] narrows what is recorded to the writes tagged with one of
  /// those objects, compared by identity (see [HandlerDelta.origin]). Leave it
  /// out to record every local write, which is what an application that does
  /// not tag its writes wants.
  ///
  /// Throws a [DocumentDisposedException] on a disposed document.
  CRDTUndoManager(
    CRDTDocument document, {
    Set<Object>? trackedOrigins,
    this.captureTimeout = const Duration(milliseconds: 500),
    this.stackLimit = 100,
  })  : _document = document,
        _trackedOrigins = trackedOrigins == null
            ? null
            : (Set<Object>.identity()..addAll(trackedOrigins)) {
    if (stackLimit < 1) {
      // Caught here rather than in [_push], which runs at the commit of an
      // ordinary write: a stack that keeps nothing would make every [undo] do
      // nothing, and say nothing about why.
      throw ArgumentError.value(stackLimit, 'stackLimit', 'must be at least 1');
    }
    document
      .._ensureNotDisposed('CRDTUndoManager')
      .._registerUndoManager(this);
  }

  final CRDTDocument _document;

  /// The origins recorded, or `null` when every local write is.
  final Set<Object>? _trackedOrigins;

  /// How long a step stays open for the next write to join it.
  ///
  /// Two steps merge into one when they are tagged with the same origin and
  /// this much time has not passed between them. It is what makes a burst of
  /// typing one undo instead of one undo per character.
  ///
  /// Origin and time are all that is compared, so two writes this close to
  /// each other merge even when they are on **different handlers**. Give them
  /// different origins, or call [stopCapturing] between them, to keep them
  /// apart.
  ///
  /// [Duration.zero] keeps every step separate.
  final Duration captureTimeout;

  /// How many steps each stack keeps. The oldest is dropped past this.
  final int stackLimit;

  /// How many operation groups one step holds before it stops swallowing the
  /// next one. See [_push].
  static const int _maxGroupsPerEntry = 1024;

  final Set<String> _tracked = <String>{};
  final List<_UndoEntry> _undoStack = <_UndoEntry>[];
  final List<_UndoEntry> _redoStack = <_UndoEntry>[];

  /// The step being filled, closed when the transaction that opened it commits.
  _UndoEntry? _open;

  _UndoMode _mode = _UndoMode.recording;

  /// Whether the next step must start on its own, ignoring [captureTimeout].
  bool _barrier = false;

  StreamController<void>? _changes;
  bool _isDisposed = false;

  /// Whether [undo] would do something.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Whether [redo] would do something.
  bool get canRedo => _redoStack.isNotEmpty;

  /// Emits whenever [canUndo] or [canRedo] may have moved.
  ///
  /// A signal, not a value: read the two getters when it fires. It can fire
  /// more than once for one edit.
  ///
  /// Throws a [StateError] on a disposed manager, rather than returning a
  /// stream that could never fire again.
  Stream<void> get changes {
    _ensureNotDisposed();
    return (_changes ??= StreamController<void>.broadcast()).stream;
  }

  /// Records the operations written on [handler] from now on.
  ///
  /// Throws an [UnsupportedError] when [handler] cannot invert its operations
  /// (see [Handler.invertible]), an [ArgumentError] when it belongs to another
  /// document, and a [StateError] when another manager already tracks it.
  ///
  /// One handler, one manager: a handler mints the identities an inverse is
  /// anchored to, so two managers recording the same write would each mint
  /// their own and neither could follow the other's.
  void track(Handler<dynamic> handler) {
    _ensureNotDisposed();
    if (!identical(handler.doc, _document)) {
      throw ArgumentError.value(
        handler,
        'handler',
        'belongs to another document',
      );
    }
    if (!handler.invertible) {
      throw UnsupportedError(
        '${handler.handlerType} cannot build the inverse of its operations, '
        'so it cannot be undone. A handler indexed by position alone has no '
        'element identity to anchor an inverse to.',
      );
    }
    for (final other in _document._undoManagers ?? const <CRDTUndoManager>[]) {
      if (!identical(other, this) && other._tracked.contains(handler.id)) {
        throw StateError(
          "'${handler.id}' is already tracked by another CRDTUndoManager. A "
          'handler mints the identities its inverses are anchored to, so it '
          'can only be recorded by one.',
        );
      }
    }
    _tracked.add(handler.id);
  }

  /// Stops recording the operations written on [handler].
  ///
  /// The steps already on the stacks are kept, and undoing one still writes its
  /// inverses. What it no longer writes is the step that would take that undo
  /// back, so [redo] skips the part of it that belongs to [handler].
  void untrack(Handler<dynamic> handler) {
    _tracked.remove(handler.id);
  }

  /// Takes back the last step, by writing the inverse of what it did.
  ///
  /// The step moves to the redo stack, holding the inverse of the undo itself,
  /// built against the state as it is now. Does nothing when [canUndo] is
  /// `false`.
  ///
  /// Throws a [StateError] inside an open [CRDTDocument.runInTransaction]: an
  /// undo is a transaction of its own, and running it inside another one would
  /// fold the two into a single step.
  void undo() {
    _ensureNotDisposed();
    _ensureNotInTransaction('undo');
    if (_undoStack.isEmpty) {
      return;
    }
    _apply(_undoStack.removeLast(), _UndoMode.undoing);
  }

  /// Writes back the last step taken back by [undo].
  ///
  /// The step moves to the undo stack. Does nothing when [canRedo] is `false`.
  ///
  /// Throws a [StateError] inside an open [CRDTDocument.runInTransaction], for
  /// the reason [undo] does.
  void redo() {
    _ensureNotDisposed();
    _ensureNotInTransaction('redo');
    if (_redoStack.isEmpty) {
      return;
    }
    _apply(_redoStack.removeLast(), _UndoMode.redoing);
  }

  /// Keeps the next step from joining the one before it, whatever
  /// [captureTimeout] says.
  ///
  /// Call it when the user does something that ends an edit — moving the caret,
  /// leaving a field — and a later write should not join what came before.
  ///
  /// It does not close a step that a running [CRDTDocument.runInTransaction]
  /// is still filling: a transaction is one step by definition.
  void stopCapturing() {
    _barrier = true;
  }

  /// Drops both stacks.
  void clear() {
    if (_undoStack.isEmpty && _redoStack.isEmpty && _open == null) {
      return;
    }
    _undoStack.clear();
    _redoStack.clear();
    _open = null;
    _emitChange();
  }

  /// Releases this manager and stops it recording.
  ///
  /// The document is left alone.
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _document._unregisterUndoManager(this);
    _tracked.clear();
    _undoStack.clear();
    _redoStack.clear();
    _open = null;
    _changes?.close();
    _changes = null;
  }

  /// Captures the inverse of [operation] before the document folds it in.
  ///
  /// Called by [CRDTDocument.registerOperation] on every manager the document
  /// holds.
  void _capture(Handler<dynamic> handler, Operation operation) {
    final tracked = _tracked.contains(handler.id);
    final origin = _document._deltaOrigin;

    if (_mode == _UndoMode.recording) {
      if (!tracked) {
        return;
      }
      // A write of this manager reaching here in recording mode would be the
      // echo of an undo that already finished, which is nobody's step.
      if (identical(origin, this)) {
        return;
      }
      final origins = _trackedOrigins;
      if (origins != null && (origin == null || !origins.contains(origin))) {
        return;
      }
    } else if (!identical(origin, this)) {
      // Someone else wrote while the undo was running: their write is not part
      // of the step being rebuilt.
      return;
    }

    // Always, even for a handler this manager has stopped recording: building
    // the inverse is also what tells the handler which new identity stands for
    // the one it just put back, and a later step would miss it.
    final inverse = handler.invert(operation);
    if (inverse.isEmpty || !tracked) {
      return;
    }
    (_open ??= _UndoEntry(origin)).groups.add(inverse);
  }

  /// Closes the open step, if any, once the transaction that held it committed.
  void _closeEntry() {
    final mode = _mode;
    if (mode != _UndoMode.recording) {
      // The undo is over here, before the document hands out the deltas it
      // produced. A listener that writes back from that flush is starting a
      // new edit, not adding to the step being rebuilt — and what follows an
      // undo never continues the step that was taken back.
      _mode = _UndoMode.recording;
      _barrier = true;
    }

    final entry = _open;
    if (entry == null) {
      return;
    }
    _open = null;

    final now = DateTime.now().millisecondsSinceEpoch;
    entry.closedAt = now;

    switch (mode) {
      case _UndoMode.recording:
        _push(_undoStack, entry, coalesce: !_barrier);
        _barrier = false;
        // A new edit is a new branch: what was taken back is not reachable
        // from here any more.
        _redoStack.clear();
      case _UndoMode.undoing:
        _push(_redoStack, entry, coalesce: false);
      case _UndoMode.redoing:
        _push(_undoStack, entry, coalesce: false);
    }

    _emitChange();
  }

  /// Writes the inverses of [entry], recording what that does on the other
  /// stack.
  void _apply(_UndoEntry entry, _UndoMode mode) {
    _mode = mode;
    try {
      _document.runInTransaction(
        () {
          // Backwards: the inverse of the second operation was captured
          // against the state the first one left, so it has to go first.
          // Inside a group the order is the handler's, and it is kept.
          for (final group in entry.groups.reversed) {
            for (final operation in group) {
              final handler = _document._handlers[operation.id];
              // A tracked handler registers itself and the registry is only
              // emptied on dispose, so an inverse always finds its handler.
              // Writing one without [Handler.prepareInverse] would ignore the
              // identities a later undo rebuilt.
              assert(
                handler != null,
                "no handler registered for '${operation.id}'",
              );
              _document.registerOperation(
                handler == null ? operation : handler.prepareInverse(operation),
              );
            }
          }
        },
        origin: this,
      );
    } catch (_) {
      // An inverse that throws leaves the step half written, and the document
      // committed that half. What is on the stacks describes a state that
      // never existed, so drop it rather than take it back later.
      clear();
      rethrow;
    } finally {
      // [_closeEntry] does this at the commit, early enough for the listeners
      // the commit serves. This is the net for a transaction that reached no
      // commit at all.
      _mode = _UndoMode.recording;
      _barrier = true;
    }
    _emitChange();
  }

  void _push(
    List<_UndoEntry> stack,
    _UndoEntry entry, {
    required bool coalesce,
  }) {
    if (coalesce && stack.isNotEmpty && captureTimeout > Duration.zero) {
      final last = stack.last;
      // [stackLimit] counts steps, so it does not bound a step that keeps
      // growing: a long burst of typing would merge into one entry forever.
      if (last.groups.length < _maxGroupsPerEntry &&
          identical(last.origin, entry.origin) &&
          entry.closedAt - last.closedAt <= captureTimeout.inMilliseconds) {
        last.groups.addAll(entry.groups);
        last.closedAt = entry.closedAt;
        return;
      }
    }

    stack.add(entry);
    if (stack.length > stackLimit) {
      stack.removeRange(0, stack.length - stackLimit);
    }
  }

  void _emitChange() {
    final controller = _changes;
    if (controller != null && !controller.isClosed) {
      controller.add(null);
    }
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('This CRDTUndoManager is disposed.');
    }
  }

  void _ensureNotInTransaction(String what) {
    if (_document.isInTransaction) {
      throw StateError(
        'Cannot $what inside an open transaction. A $what is a transaction of '
        'its own: running it inside another one would fold what the caller is '
        'writing and what is being taken back into a single step.',
      );
    }
  }

  @override
  String toString() => 'CRDTUndoManager(undo: ${_undoStack.length}, '
      'redo: ${_redoStack.length}, handlers: ${_tracked.length})';
}
