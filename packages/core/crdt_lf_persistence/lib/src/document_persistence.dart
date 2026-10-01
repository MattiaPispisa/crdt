import 'dart:async';
import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// How long the first retry after a failed write waits. It doubles per
/// failure in a row, up to [_maxRetryDelay].
const _firstRetryDelay = Duration(milliseconds: 250);

/// The longest a retry waits.
const _maxRetryDelay = Duration(seconds: 30);

/// Keeps a [CRDTDocument] on disk as it changes.
///
/// [open] reads the stored document back. Then every change, snapshot and
/// prune the document reports on [CRDTDocument.events] is written down. See
/// the README, "How it works".
///
/// ```dart
/// final persistence = await CRDTDocumentPersistence.open(document, storage);
/// text.insert(0, 'Hello');
/// await persistence.dispose(); // writes what is still waiting
/// ```
class CRDTDocumentPersistence {
  CRDTDocumentPersistence._(
    this._document,
    this.storage,
    this._writeDelay,
    this._compactAfter,
    int? keepSnapshots,
    this._onError,
  )   : assert(
          keepSnapshots == null || keepSnapshots > 0,
          'keepSnapshots must be positive, or null to keep every snapshot',
        ),
        _keepSnapshots = keepSnapshots == null ? null : max(1, keepSnapshots),
        _restore = _Restore(_document, storage),
        _storedVersion = _StoredVersion();

  /// Subscribes before the restore, so an edit made while [open] runs is still
  /// written. The restore's own events carry its origin and are skipped.
  factory CRDTDocumentPersistence._following(
    CRDTDocument document,
    CRDTDocumentStorage storage,
    Duration writeDelay,
    int? compactAfter,
    int? keepSnapshots,
    void Function(Object error, StackTrace stack)? onError,
  ) {
    if (compactAfter != null && compactAfter <= 0) {
      throw ArgumentError.value(
        compactAfter,
        'compactAfter',
        'must be positive, or null to leave compaction off',
      );
    }

    final persistence = CRDTDocumentPersistence._(
      document,
      storage,
      writeDelay,
      compactAfter,
      keepSnapshots,
      onError,
    );

    persistence._subscription = document.events.listen(persistence._onEvent);
    return persistence;
  }

  /// Reads the stored document into [document], then writes down what it
  /// reports.
  ///
  /// [document] may already hold state. It is merged with the stored one, the
  /// history is kept, and what only [document] holds is written too.
  ///
  /// - [writeDelay]: how long a change waits, so the changes of that time go
  ///   to the disk in one write.
  /// - [compactAfter]: snapshots and prunes once the store holds more changes
  ///   than that; `null` keeps the whole log. A prune empties the stacks of
  ///   every [CRDTUndoManager] on the document.
  /// - [keepSnapshots]: how many snapshots stay on the disk, for
  ///   [CRDTDocumentStorageReading.documentAt]; `null` keeps all of them, and
  ///   less than 1 counts as 1.
  /// - [onError]: gets every failed write. The write stays queued and is
  ///   retried.
  ///
  /// Throws an [ArgumentError] when [compactAfter] is not positive.
  static Future<CRDTDocumentPersistence> open(
    CRDTDocument document,
    CRDTDocumentStorage storage, {
    Duration writeDelay = const Duration(milliseconds: 250),
    int? compactAfter,
    int? keepSnapshots = 1,
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    final persistence = CRDTDocumentPersistence._following(
      document,
      storage,
      writeDelay,
      compactAfter,
      keepSnapshots,
      onError,
    );

    await persistence._restoreFromStorage();
    return persistence;
  }

  /// [open] for a storage that reads without suspending: the document is
  /// already restored when this returns.
  ///
  /// Throws a [StateError] when a read returns a [Future], as drift's do, and
  /// leaves the document untouched. The options are those of [open].
  static CRDTDocumentPersistence openSync(
    CRDTDocument document,
    CRDTDocumentStorage storage, {
    Duration writeDelay = const Duration(milliseconds: 250),
    int? compactAfter,
    int? keepSnapshots = 1,
    void Function(Object error, StackTrace stack)? onError,
  }) {
    final persistence = CRDTDocumentPersistence._following(
      document,
      storage,
      writeDelay,
      compactAfter,
      keepSnapshots,
      onError,
    );

    final restoring = persistence._restoreFromStorage();
    if (restoring is Future<void>) {
      // The read is in flight: abandoned, it never imports after this throws.
      persistence._restore.abandon();
      // Nobody awaits it, so a failure would surface as an unhandled error.
      unawaited(restoring.catchError((Object _, StackTrace __) {}));
      unawaited(persistence._subscription?.cancel());
      persistence._subscription = null;
      throw StateError(
        'openSync needs a storage that reads without suspending, and '
        '${storage.runtimeType} returned a future. Use open() instead.',
      );
    }

    return persistence;
  }

  final CRDTDocument _document;

  /// Where the document is kept.
  final CRDTDocumentStorage storage;

  final Duration _writeDelay;
  final int? _compactAfter;
  final int? _keepSnapshots;
  final void Function(Object error, StackTrace stack)? _onError;

  final _Restore _restore;

  StreamSubscription<CRDTDocumentEvent>? _subscription;

  final List<Change> _pending = <Change>[];

  /// How many changes the store holds, for the `compactAfter` of [open].
  int _stored = 0;

  /// The ids of the snapshots on the disk, oldest first. Kept here: reading
  /// them back would decode every stored snapshot.
  List<String> _snapshotsOnDisk = <String>[];

  /// Snapshot, prune and cleanup writes. One starts once the one before it has
  /// landed.
  final List<_Step> _steps = <_Step>[];

  final _StoredVersion _storedVersion;

  /// Failed writes in a row, for the backoff of [_scheduleRetry].
  int _failures = 0;

  bool _disposed = false;

  Timer? _timer;

  /// The writes, chained: one runs at a time, in order.
  Future<void> _writing = Future<void>.value();

  /// Failed writes since [open], for [flush].
  int _failureCount = 0;

  late Object _lastError;
  late StackTrace _lastStackTrace;

  /// Whether changes, snapshots or prunes still wait to be written.
  ///
  /// After [dispose], `true` means they never reached the disk.
  bool get hasUnwrittenChanges => _pending.isNotEmpty || _steps.isNotEmpty;

  FutureOr<void> _restoreFromStorage() => _restore.run().chain(_catchUp);

  void _catchUp(_Restored? restored) {
    if (restored == null) {
      return;
    }
    _stored = restored.changeCount;
    _storedVersion.addVersion(restored.version);

    final ids = restored.snapshotIds;
    final limit = _keepSnapshots;
    final staleCount =
        limit == null || ids.length <= limit ? 0 : ids.length - limit;
    _snapshotsOnDisk = ids.sublist(staleCount);
    if (staleCount > 0) {
      // A crash between a snapshot write and its delete, or a smaller
      // `keepSnapshots`, left too many.
      final stale = ids.sublist(0, staleCount);
      _addStep(
        _Step(() => storage.snapshots.deleteSnapshots(stale).chain((_) {})),
      );
    }

    if (restored.unwrittenChanges.isNotEmpty) {
      _pending.addAll(restored.unwrittenChanges);
      _timer ??= Timer(_writeDelay, _flush);
    }
    final snapshot = restored.unwrittenSnapshot;
    if (snapshot != null) {
      _addStep(_snapshotStep(snapshot));
    }
  }

  void _onEvent(CRDTDocumentEvent event) {
    switch (event) {
      case DocumentChangesApplied():
        if (identical(event.origin, _restore.origin)) {
          return;
        }
        // Remote changes too: a reopen offline brings back the whole document.
        _pending.addAll(event.changes);
        _timer ??= Timer(_writeDelay, _flush);
      case DocumentSnapshotUpdated():
        if (identical(event.origin, _restore.origin)) {
          return;
        }
        _addStep(_snapshotStep(event.snapshot));
      case DocumentHistoryPruned():
        _addStep(_Step(() => _writePrune(event.removed, event.rewritten)));
    }
  }

  _Step _snapshotStep(Snapshot snapshot) => _Step(
        () => _writeSnapshot(snapshot),
        covers: snapshot.versionVector,
      );

  /// Only the first step of an empty queue starts a run: a running one picks
  /// up the steps added behind it.
  void _addStep(_Step step) {
    _steps.add(step);
    if (_steps.length == 1) {
      _enqueue(_writeSteps);
    }
  }

  /// Writes the steps in order, and stops at the first that fails.
  FutureOr<void> _writeSteps() {
    if (_steps.isEmpty) {
      return null;
    }
    final step = _steps.first;

    final written = step.write();
    if (written is Future<void>) {
      return written.then((_) {
        _stepLanded(step);
        return _writeSteps();
      });
    }
    _stepLanded(step);
    return _writeSteps();
  }

  void _stepLanded(_Step step) {
    _steps.remove(step);
    _failures = 0;
    final covers = step.covers;
    if (covers != null) {
      _storedVersion.addVersion(covers);
    }
  }

  /// Applies the prune to [_pending] too.
  ///
  /// A pruned change still waiting would be written after the delete meant to
  /// remove it, and stay on the disk for good. A waiting survivor would
  /// overwrite its rewritten bytes. Runs from [_writePrune], once a failed
  /// batch before it is back in [_pending].
  void _prunePending(List<Change> removed, List<Change> rewritten) {
    if (_pending.isEmpty) {
      return;
    }

    final gone = removed.map((change) => change.id).toSet();
    _pending.removeWhere((change) => gone.contains(change.id));

    if (rewritten.isEmpty) {
      return;
    }
    final replacements = {
      for (final change in rewritten) change.id: change,
    };
    for (var i = 0; i < _pending.length; i++) {
      final replacement = replacements[_pending[i].id];
      if (replacement != null) {
        _pending[i] = replacement;
      }
    }
  }

  void _enqueue(FutureOr<void> Function() work) {
    _writing = _writing.then((_) => work()).catchError(_report);
  }

  void _report(Object error, StackTrace stack) {
    _failureCount++;
    _lastError = error;
    _lastStackTrace = stack;
    _failures++;
    _onError?.call(error, stack);
    _scheduleRetry();
  }

  /// Arms the timer after a failed write: a document that goes quiet has no
  /// event left to arm it.
  void _scheduleRetry() {
    if (_disposed || !hasUnwrittenChanges || _timer != null) {
      return;
    }

    // Capped before the shift, so a long run of failures cannot overflow it.
    final doublings = min(_failures - 1, 16);
    _timer = Timer(
      Duration(
        microseconds: min(
          _firstRetryDelay.inMicroseconds * (1 << doublings),
          _maxRetryDelay.inMicroseconds,
        ),
      ),
      _flush,
    );
  }

  /// Writes what is waiting now, and waits for it.
  ///
  /// It waits for the work queued when it was called. Edits made meanwhile,
  /// and a compaction its own writes start, are written after it returns.
  ///
  /// A failed write ends it and stays queued for a retry; with [throwOnError]
  /// the failure is also thrown.
  Future<void> flush({bool throwOnError = false}) async {
    final failuresBefore = _failureCount;
    // Events arrive on a microtask: lets in the edits made before this call.
    await Future<void>.delayed(Duration.zero);
    final target = _FlushTarget(_pending, _steps);

    // The timer would write this work a second time.
    _timer?.cancel();
    _timer = null;
    if (_pending.isNotEmpty) {
      _enqueue(_writePending);
    }
    if (_steps.isNotEmpty) {
      _enqueue(_writeSteps);
    }
    // The chain is serial, so this also waits for a write already running.
    await _writing;

    // The target first: a failure of work queued after the call belongs to
    // the next flush.
    if (target.isReached(_storedVersion, _steps)) {
      return;
    }
    assert(
      _failureCount != failuresBefore,
      'one round writes the whole target unless a write fails',
    );
    if (throwOnError) {
      Error.throwWithStackTrace(_lastError, _lastStackTrace);
    }
  }

  void _flush() {
    _timer = null;
    _enqueue(_writePending);
    _enqueue(_writeSteps);
  }

  /// Writes [_pending] in one batch, and puts it back when the write fails.
  ///
  /// A dropped batch would break the changes after it, which name it as a
  /// dependency. Writing a change twice replaces it, so a retry is safe.
  FutureOr<void> _writePending() {
    if (_pending.isEmpty) {
      return null;
    }
    final batch = List<Change>.of(_pending);
    _pending.clear();

    FutureOr<void> written;
    try {
      written = storage.changes.saveChanges(batch);
    } catch (_) {
      _pending.insertAll(0, batch);
      rethrow;
    }

    if (written is Future<void>) {
      return written.then(
        (_) => _afterWrite(batch),
        onError: (Object error, StackTrace stack) {
          _pending.insertAll(0, batch);
          Error.throwWithStackTrace(error, stack);
        },
      );
    }
    _afterWrite(batch);
    return null;
  }

  void _afterWrite(List<Change> batch) {
    _failures = 0;
    _stored += batch.length;
    _storedVersion.addChanges(batch);
    _compactIfNeeded();
  }

  /// Snapshots the document past `compactAfter`, while this still follows it:
  /// the snapshot and prune events do the writing.
  void _compactIfNeeded() {
    final limit = _compactAfter;
    if (limit == null ||
        _stored <= limit ||
        _document.isDisposed ||
        _subscription == null) {
      return;
    }
    // Now, not when the prune lands: the writes in between must not snapshot
    // again. [_writePrune] reads the real count back.
    _stored = 0;
    _document.takeSnapshot();
  }

  /// Writes [snapshot] and drops the ones past `keepSnapshots`, in one
  /// transaction.
  ///
  /// The write comes first: on a backend without transactions, a crash in
  /// between leaves a snapshot too many instead of none.
  FutureOr<void> _writeSnapshot(Snapshot snapshot) {
    final kept = [
      for (final id in _snapshotsOnDisk)
        if (id != snapshot.id) id,
      snapshot.id,
    ];
    final limit = _keepSnapshots;
    final stale = limit == null || kept.length <= limit
        ? const <String>[]
        : kept.sublist(0, kept.length - limit);

    return storage
        .transaction<void>(
      () => storage.snapshots.saveSnapshot(snapshot).chain((_) {
        if (stale.isEmpty) {
          return null;
        }
        return storage.snapshots.deleteSnapshots(stale).chain((_) {});
      }),
    )
        .chain((_) {
      // Only once landed, so a rollback leaves the ids true.
      _snapshotsOnDisk = kept.sublist(stale.length);
    });
  }

  /// Writes the survivors again and deletes what the prune removed, in one
  /// transaction.
  ///
  /// The survivors come first: on a backend without transactions, a crash in
  /// between leaves a change too many, which the next prune removes, instead
  /// of a survivor naming a deleted dependency.
  FutureOr<void> _writePrune(List<Change> removed, List<Change> rewritten) {
    _prunePending(removed, rewritten);

    return storage
        .transaction<void>(
          () => storage.changes
              .saveChanges(rewritten)
              .chain((_) => storage.changes.deleteChanges(removed))
              .chain((_) {}),
        )
        .chain(
          (_) => storage.changes.count.chain((stored) {
            _stored = stored;
          }),
        );
  }

  /// Snapshots the document, prunes the history the snapshot covers, and waits
  /// for both to reach the disk.
  ///
  /// The `compactAfter` of [open], on demand. **Every [CRDTUndoManager] on the
  /// document loses its stacks.**
  ///
  /// Returns the snapshot. Throws when a write fails; it is retried like any
  /// other.
  Future<Snapshot> compact() async {
    final snapshot = _document.takeSnapshot();
    await flush(throwOnError: true);
    return snapshot;
  }

  /// The version of the document the storage brings back after a crash. It
  /// only grows.
  VersionVector get storedVersion => _storedVersion.value;

  /// Completes once [storedVersion] covers [version].
  ///
  /// ```dart
  /// text.insert(0, 'Hello');
  /// await persistence.whenStored(document.getVersionVector());
  /// ```
  ///
  /// A failed write keeps it waiting while the write is retried. Throws a
  /// [StateError] when [dispose] comes first.
  Future<void> whenStored(VersionVector version) =>
      _storedVersion.whenCovers(version);

  /// Stops following the document and writes what is still waiting.
  ///
  /// Edits made after this stay in the document only. [storage] stays open:
  /// close it with [CRDTDocumentStorage.close].
  Future<void> dispose() async {
    // Lets in the edits made before this call.
    await Future<void>.delayed(Duration.zero);
    // Before the flush, so the queue stops growing.
    await _subscription?.cancel();
    _subscription = null;

    await flush();
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _storedVersion.close();
  }
}

/// The first read: merges the storage into the document, and reports what the
/// storage holds and what only the document has.
class _Restore {
  _Restore(this._document, this._storage) : origin = Object();

  final CRDTDocument _document;
  final CRDTDocumentStorage _storage;

  /// Tags the import, so its events are not written back.
  final Object origin;

  bool _abandoned = false;

  /// Makes a read in flight land nowhere.
  void abandon() => _abandoned = true;

  /// Returns without suspending when both reads do, for
  /// [CRDTDocumentPersistence.openSync].
  FutureOr<_Restored?> run() {
    return _storage.changes.getChanges().chain(
          (changes) => _storage.snapshots
              .getSnapshots()
              .chain((snapshots) => _apply(changes, snapshots)),
        );
  }

  _Restored? _apply(List<Change> changes, List<Snapshot> snapshots) {
    if (_abandoned) {
      return null;
    }
    final unwrittenChanges = _changesOnlyTheDocumentHas(changes);
    final ordered = _oldestFirst(snapshots);
    if (changes.isNotEmpty || ordered.isNotEmpty) {
      _document.import(
        snapshot: ordered.isEmpty ? null : ordered.last,
        changes: changes,
        merge: true,
        pruneHistory: false,
        origin: origin,
      );
    }

    var version = VersionVector({});
    for (final change in changes) {
      version.update(change.author, change.hlc);
    }
    for (final snapshot in ordered) {
      version = version.merged(snapshot.versionVector);
    }
    final ids = [for (final snapshot in ordered) snapshot.id];
    final snapshot = _document.snapshot;

    return _Restored(
      changeCount: changes.length,
      version: version,
      snapshotIds: ids,
      unwrittenChanges: unwrittenChanges,
      unwrittenSnapshot:
          snapshot == null || ids.contains(snapshot.id) ? null : snapshot,
    );
  }

  /// The changes the document held before it was followed, and [stored] lacks.
  ///
  /// No event reported them: a document publishes only to listeners. Left
  /// out, the changes written after them would name missing dependencies.
  List<Change> _changesOnlyTheDocumentHas(List<Change> stored) {
    final mine = _document.exportChanges();
    if (mine.isEmpty) {
      return const [];
    }
    final onDisk = stored.map((change) => change.id).toSet();
    return [
      for (final change in mine)
        if (!onDisk.contains(change.id)) change,
    ];
  }

  /// [snapshots], oldest first, as [newestSnapshot] ranks them.
  List<Snapshot> _oldestFirst(List<Snapshot> snapshots) {
    final left = List<Snapshot>.of(snapshots);
    final ordered = <Snapshot>[];
    while (left.isNotEmpty) {
      final newest = newestSnapshot(left)!;
      left.remove(newest);
      ordered.insert(0, newest);
    }
    return ordered;
  }
}

/// What [_Restore.run] found.
class _Restored {
  _Restored({
    required this.changeCount,
    required this.version,
    required this.snapshotIds,
    required this.unwrittenChanges,
    required this.unwrittenSnapshot,
  });

  /// How many changes the storage holds.
  final int changeCount;

  /// The version the storage brings back.
  final VersionVector version;

  /// The ids of the stored snapshots, from the oldest to the newest.
  final List<String> snapshotIds;

  /// The changes the document held and the storage did not.
  final List<Change> unwrittenChanges;

  /// The document's snapshot after the restore; `null` when the storage holds
  /// it.
  final Snapshot? unwrittenSnapshot;
}

class _Step {
  _Step(this.write, {this.covers});

  final FutureOr<void> Function() write;

  /// The version a snapshot step stores; `null` for the other steps.
  final VersionVector? covers;
}

/// The version the storage brings back, and the callers waiting for it.
///
/// One clock per author is enough: the changes of an author land in the order
/// the document applied them.
class _StoredVersion {
  _StoredVersion()
      : _version = VersionVector({}),
        _waiters = <_Waiter>[];

  final VersionVector _version;
  final List<_Waiter> _waiters;
  bool _closed = false;

  VersionVector get value => _version.immutable();

  bool covers(VersionVector version) =>
      _version.isStrictlyNewerOrEqualThan(version);

  void addChanges(Iterable<Change> changes) {
    for (final change in changes) {
      _version.update(change.author, change.hlc);
    }
    _wakeWaiters();
  }

  void addVersion(VersionVector version) {
    for (final MapEntry(key: peer, value: clock) in version.entries) {
      _version.update(peer, clock);
    }
    _wakeWaiters();
  }

  Future<void> whenCovers(VersionVector version) {
    if (covers(version)) {
      return Future<void>.value();
    }
    if (_closed) {
      return Future<void>.error(_notStored(version));
    }
    final waiter = _Waiter(version);
    _waiters.add(waiter);
    return waiter.completer.future;
  }

  /// Fails every caller still waiting; the ones after this fail at once.
  void close() {
    _closed = true;
    final waiters = List.of(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      waiter.completer.completeError(_notStored(waiter.version));
    }
  }

  void _wakeWaiters() {
    _waiters.removeWhere((waiter) {
      if (!covers(waiter.version)) {
        return false;
      }
      waiter.completer.complete();
      return true;
    });
  }

  static StateError _notStored(VersionVector version) =>
      StateError('version $version was not stored before dispose');
}

class _Waiter {
  _Waiter(this.version) : completer = Completer<void>();

  final VersionVector version;

  final Completer<void> completer;
}

/// What a [CRDTDocumentPersistence.flush] waits for: the work queued when it
/// was called.
class _FlushTarget {
  _FlushTarget(List<Change> pending, List<_Step> steps)
      : _changes = _versionOf(pending),
        _lastStep = steps.lastOrNull;

  final VersionVector _changes;
  final _Step? _lastStep;

  /// The steps land in order, so the last one stands for all of them.
  bool isReached(_StoredVersion stored, List<_Step> steps) {
    final lastStep = _lastStep;
    return stored.covers(_changes) &&
        (lastStep == null || !steps.contains(lastStep));
  }

  static VersionVector _versionOf(List<Change> changes) {
    final version = VersionVector({});
    for (final change in changes) {
      version.update(change.author, change.hlc);
    }
    return version;
  }
}
