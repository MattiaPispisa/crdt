import 'dart:async';
import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// How long the first retry after a failed write waits.
///
/// It doubles per consecutive failure, up to [_maxRetryDelay]. It does not
/// follow the `writeDelay` of [CRDTDocumentPersistence.open]: that one can be
/// [Duration.zero], and retrying a broken disk as fast as the event loop
/// allows helps nobody.
const _firstRetryDelay = Duration(milliseconds: 250);

/// The longest a retry waits.
const _maxRetryDelay = Duration(seconds: 30);

/// Keeps a [CRDTDocument] on disk as it changes.
///
/// It reads the document back at [open], then follows [CRDTDocument.events]
/// and writes down what each event reports. The document is never exported
/// again: it says what moved, and only that is written.
///
/// This is the whole of the local-only use case — a document, a storage, and
/// this:
///
/// ```dart
/// final document = CRDTDocument();
/// final text = CRDTFugueTextHandler(document, 'body');
/// final persistence = await CRDTDocumentPersistence.open(document, storage);
///
/// text.insert(0, 'Hello');
///
/// await persistence.dispose(); // writes what is still waiting
/// ```
///
/// On a storage that reads without suspending, [openSync] does the same
/// without an await, so the document is already full when it is first used.
///
/// In a synced app it is also what makes the client offline-first: the
/// document comes back after a restart, and a sync client catches its peer up
/// from the restored state.
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
        _storedVersion = VersionVector({}),
        _waiters = <_Waiter>[];

  /// Builds the persistence and points it at [document], ready to restore.
  ///
  /// Subscribing happens before the restore, not after: a change applied while
  /// the storage is being read would otherwise never be written down. The
  /// restore tags itself, and [_onEvent] skips what carries that tag.
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

  /// Reads the stored document into [document], then follows it.
  ///
  /// Call this **before** connecting a sync client: the restored state is what
  /// the client reconciles against, so what was written offline reaches the
  /// peer instead of sitting on this device.
  ///
  /// The stored state is merged rather than imported, and the history is kept:
  /// on a reopen the document may already hold changes of this session, and a
  /// sync client may still be asked for a snapshot covering that history.
  ///
  /// A change the document already held and the storage did not is queued for
  /// the next write, so a document edited before this was called is kept whole
  /// rather than half.
  ///
  /// [writeDelay] is how long a change waits for the ones after it. One
  /// keystroke is one transaction, so writing on every event would put a
  /// round-trip to the disk between the typist and the next character.
  ///
  /// [compactAfter] snapshots and prunes the document once the store holds
  /// more than that many changes. It has to be positive; leave it `null` to
  /// keep compaction off. Off by default: a prune drops the stacks of every
  /// [CRDTUndoManager] on the document. Leave it off and the log grows for as
  /// long as the document is edited.
  ///
  /// [keepSnapshots] is how many of the newest snapshots stay on the disk; an
  /// older one lets [CRDTDocumentStorageReading.documentAt] reach further
  /// back. It has to be positive, and counts as 1 when it is not; leave it
  /// `null` to keep every snapshot.
  ///
  /// [onError] is called when a write fails. Without it a failed write is
  /// silent. What the write carried stays in the queue, so the next [flush]
  /// tries again; [hasUnwrittenChanges] says whether anything is still
  /// waiting.
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

  /// The [open] that a storage reading without suspending allows.
  ///
  /// The document is restored before this returns, so it is already full the
  /// first time anything reads it. A Flutter app builds its first frame from
  /// the stored state instead of an empty document.
  ///
  /// Throws a [StateError] on a storage whose reads return a [Future] — drift
  /// is always one of them. The restore that was already started is abandoned,
  /// and the document is left untouched. Use [open] there.
  ///
  /// The options mean what they mean on [open].
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
      // The read is already in flight and cannot be called back. Abandoning it
      // is what keeps it from importing into the document after this throws.
      persistence._restore.abandon();
      // Nobody is left to await it, so a failure would become an unhandled
      // asynchronous error rather than the [StateError] below.
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

  /// The first read, which fills the document from the storage.
  final _Restore _restore;

  StreamSubscription<CRDTDocumentEvent>? _subscription;

  /// Changes waiting for the next write.
  final List<Change> _pending = <Change>[];

  /// How many changes the store holds, for the `compactAfter` of [open].
  int _stored = 0;

  /// The ids of the snapshots on the disk right now, oldest first.
  ///
  /// Kept here so replacing one costs no read: a snapshot is the biggest blob
  /// of the store, and reading every one of them back to learn an id would
  /// decode the whole previous document state on each write.
  List<String> _snapshotsOnDisk = <String>[];

  /// Snapshot, prune and cleanup writes, in order. One runs only once the one
  /// before it has landed.
  final List<_Step> _steps = <_Step>[];

  /// What the storage can bring back: the landed changes and snapshots.
  ///
  /// One clock per author is enough. The changes of an author land in the
  /// order the document applied them, so the older ones are always on disk.
  final VersionVector _storedVersion;

  /// The callers of [whenStored] still waiting.
  final List<_Waiter> _waiters;

  /// How many writes failed in a row, for the backoff of [_scheduleRetry].
  int _failures = 0;

  /// [dispose] has run, so nothing must arm a timer any more.
  bool _disposed = false;

  Timer? _timer;

  /// A write already running, so two never overlap.
  Future<void> _writing = Future<void>.value();

  /// How many writes have failed since this was opened.
  int _failureCount = 0;

  late Object _lastError;
  late StackTrace _lastStackTrace;

  /// Whether changes, snapshots or prunes are still waiting to be written.
  ///
  /// A write that failed leaves what it carried here, so a later [flush] can
  /// try again. After [dispose] it means those changes never reached the
  /// storage: the document still holds them, the disk does not.
  bool get hasUnwrittenChanges => _pending.isNotEmpty || _steps.isNotEmpty;

  FutureOr<void> _restoreFromStorage() => _restore.run().chain(_catchUp);

  /// Takes on what the restore found: the store as it is, and the work the
  /// document left for the queue.
  void _catchUp(_Restored? restored) {
    if (restored == null) {
      return;
    }
    _stored = restored.changeCount;
    _cover(restored.version);

    final ids = restored.snapshotIds;
    final limit = _keepSnapshots;
    final staleCount =
        limit == null || ids.length <= limit ? 0 : ids.length - limit;
    _snapshotsOnDisk = ids.sublist(staleCount);
    if (staleCount > 0) {
      // A process killed between the write of a snapshot and the delete of an
      // older one, or a smaller `keepSnapshots`, left too many here.
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
        // Both sources: what this peer wrote, and what came from a peer.
        // Reopening offline has to bring back the whole document, not half.
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

  /// Queues [step] behind the ones already waiting.
  ///
  /// Only the first step of an empty queue starts a run: a run in progress
  /// picks up what is added behind it, and a failed one is retried by the
  /// timer of [_scheduleRetry].
  void _addStep(_Step step) {
    _steps.add(step);
    if (_steps.length == 1) {
      _enqueue(_writeSteps);
    }
  }

  /// Writes the queued steps in order, and stops at the first that fails.
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
      _cover(covers);
      _wakeWaiters();
    }
  }

  void _cover(VersionVector version) {
    for (final MapEntry(key: peer, value: clock) in version.entries) {
      _storedVersion.update(peer, clock);
    }
  }

  void _wakeWaiters() {
    _waiters.removeWhere((waiter) {
      if (!_storedVersion.isStrictlyNewerOrEqualThan(waiter.version)) {
        return false;
      }
      waiter.completer.complete();
      return true;
    });
  }

  /// Applies the prune to the queue as well as to the store.
  ///
  /// Called from [_writePrune], not from [_onEvent]: by then every write that
  /// was in flight has settled, error handler included. A write that failed
  /// puts its batch back in the queue, and a batch put back after this ran
  /// would carry a pruned change past the delete meant to remove it.
  ///
  /// A change pruned before it was ever written is still waiting here. Left
  /// alone it would be written **after** the delete meant to remove it, and
  /// nothing would remove it later: a prune only names what the document still
  /// holds, and the document no longer holds this one. It would sit on the
  /// disk for the life of the store.
  ///
  /// A survivor is the same story told with its old bytes: [_writePrune] saves
  /// the rewritten version, and the queued one would overwrite it with a
  /// dependency that is already gone.
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

  /// Runs [work] after whatever is already writing.
  ///
  /// The order matters: a snapshot has to reach the disk before the prune that
  /// drops the changes it covers.
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

  /// Arms the timer again after a failed write.
  ///
  /// Without this a document that goes quiet after a failure keeps its changes
  /// in memory only: the timer of [_onEvent] is armed by an event, and no
  /// event is coming. The wait doubles per consecutive failure up to
  /// [_maxRetryDelay], so a disk that is gone is not asked again every
  /// quarter second.
  void _scheduleRetry() {
    if (_disposed || !hasUnwrittenChanges || _timer != null) {
      return;
    }

    // Capped before the shift, so the doubling cannot overflow on a storage
    // that has been failing for a long time.
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

  /// Writes what is waiting, now, and waits for it.
  ///
  /// Loops until a whole round produces nothing new, for two reasons.
  /// [CRDTDocument.events] hands an event to its listeners on a microtask. The
  /// ones already published have to be let through first, or a flush right
  /// after an edit would miss that edit. And a write can cause more work: a
  /// compaction snapshots the document, which publishes events of its own.
  ///
  /// A write made while this runs is written by it too, so a flush that races
  /// a typist takes one more round.
  ///
  /// It gives up for this round as soon as a write fails, rather than handing
  /// the same changes to a storage that just refused them. The changes stay
  /// queued, the error reaches the `onError` of [open], and
  /// [hasUnwrittenChanges] reads `true`.
  ///
  /// With [throwOnError] a failed write is also thrown, to every flush that
  /// was running when it failed. A flush that returns has written everything
  /// that was waiting when it was called.
  Future<void> flush({bool throwOnError = false}) async {
    final failuresBefore = _failureCount;

    while (true) {
      // A zero delay runs after the microtask queue, which is where a
      // published event reaches `_onEvent`.
      await Future<void>.delayed(Duration.zero);
      // Every round, not once: the events let through above arm a timer of
      // their own, and it would write this round's work a second time.
      _timer?.cancel();
      _timer = null;
      if (_pending.isNotEmpty) {
        _enqueue(_writePending);
      }
      if (_steps.isNotEmpty) {
        _enqueue(_writeSteps);
      }
      final tail = _writing;
      await tail;
      await Future<void>.delayed(Duration.zero);

      // Before the check below, not after: a failed write puts its changes
      // back, so the queue never empties and the loop would never end.
      if (_failureCount != failuresBefore) {
        if (throwOnError) {
          Error.throwWithStackTrace(_lastError, _lastStackTrace);
        }
        return;
      }
      if (!hasUnwrittenChanges && identical(tail, _writing)) {
        return;
      }
    }
  }

  void _flush() {
    _timer = null;
    _enqueue(_writePending);
    _enqueue(_writeSteps);
  }

  /// Writes the queue, and keeps it when the write fails.
  ///
  /// A dropped batch is not one lost edit: the changes after it name it as a
  /// dependency, so a reload replays them against something the document
  /// cannot resolve. Back in the queue it goes instead, ahead of whatever
  /// arrived while the write ran, and the next [flush] tries the whole batch
  /// again — saving a change twice replaces it, so a write that half landed
  /// costs nothing.
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
    for (final change in batch) {
      _storedVersion.update(change.author, change.hlc);
    }
    _wakeWaiters();
    _compactIfNeeded();
  }

  /// Snapshots and prunes once the store holds more than the `compactAfter`
  /// of [open].
  ///
  /// The snapshot and prune events that follow do the writing through the
  /// normal path. [_stored] drops to zero here rather than when the prune
  /// lands, so the writes queued in between do not each ask for a snapshot of
  /// their own; [_writePrune] then reads the real count back.
  void _compactIfNeeded() {
    final limit = _compactAfter;
    if (limit == null || _stored <= limit || _document.isDisposed) {
      return;
    }
    _stored = 0;
    _document.takeSnapshot();
  }

  /// Writes [snapshot], and drops the oldest ones past the `keepSnapshots` of
  /// [open].
  ///
  /// Written before the old ones are dropped, never after. A process killed
  /// between the two steps would otherwise leave the document with no snapshot
  /// at all — and once the history it covers is pruned, that state has nowhere
  /// else to come from.
  ///
  /// Both steps go in one [CRDTDocumentStorage.transaction]. The order still
  /// stands inside it: a backend without transactions runs them as they are
  /// written and depends on it.
  ///
  /// Which snapshots to drop is read from [_snapshotsOnDisk] rather than from
  /// the storage: asking the storage would decode the whole previous state to
  /// learn the ids. The field is moved only once the transaction has landed,
  /// so a rollback leaves it naming what is really there.
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
      _snapshotsOnDisk = kept.sublist(stale.length);
    });
  }

  /// Writes the survivors again, and drops what the prune removed.
  ///
  /// A change that pointed at a pruned dependency was rebuilt without it, so
  /// the bytes on disk describe a change that no longer exists.
  ///
  /// Both steps go in one [CRDTDocumentStorage.transaction]: a backend that
  /// has transactions never leaves a survivor with its old bytes next to a
  /// dependency that is already gone.
  ///
  /// The survivors are written **first**, which is what a backend without
  /// transactions rests on. Stopped halfway this way, the store holds the new
  /// bytes next to changes that should have gone — a copy too many, which the
  /// next prune removes. The other way round it would hold survivors naming a
  /// dependency that is already deleted, which nothing writes again and which
  /// a reload cannot replay.
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

  /// Snapshots the document, drops the history the snapshot covers, and waits
  /// for both to reach the disk.
  ///
  /// What the `compactAfter` of [open] does on its own, on demand: a "save and
  /// compact" button, or the moment an app goes to the background. The log
  /// stops growing, and the next open reads one snapshot instead of every
  /// change ever written.
  ///
  /// It costs what a prune costs: **every [CRDTUndoManager] on the document
  /// loses its stacks.** In an editor undo usually matters more than a short
  /// log, so compact where the user cannot be in the middle of something.
  ///
  /// Returns the snapshot that was written. Throws when the snapshot or the
  /// prune fails to write; the write is tried again later, as any other.
  Future<Snapshot> compact() async {
    final snapshot = _document.takeSnapshot();
    await flush(throwOnError: true);
    return snapshot;
  }

  /// The version of the document the storage brings back after a crash.
  ///
  /// It counts what [open] read and every change or snapshot written since.
  /// It only grows.
  VersionVector get storedVersion => _storedVersion.immutable();

  /// Completes once [storedVersion] covers [version].
  ///
  /// Pass the version of the document right after an edit, or the version of
  /// a snapshot, to know it survives a crash:
  ///
  /// ```dart
  /// text.insert(0, 'Hello');
  /// await persistence.whenStored(document.getVersionVector());
  /// ```
  ///
  /// A failed write keeps this waiting while the write is tried again; the
  /// error reaches the `onError` of [open]. Add a `timeout` to give up
  /// earlier, or use [flush] with `throwOnError` to fail on the first error.
  ///
  /// Throws a [StateError] when [dispose] runs before [version] is stored.
  Future<void> whenStored(VersionVector version) {
    if (_storedVersion.isStrictlyNewerOrEqualThan(version)) {
      return Future<void>.value();
    }
    if (_disposed) {
      return Future<void>.error(_notStored(version));
    }
    final waiter = _Waiter(version);
    _waiters.add(waiter);
    return waiter.completer.future;
  }

  StateError _notStored(VersionVector version) =>
      StateError('version $version was not stored before dispose');

  /// Writes what is still waiting and stops following the document.
  ///
  /// It does not close [storage]: the caller opened it, and on a backend that
  /// shares one connection between documents it is not this document's to
  /// close. Call [CRDTDocumentStorage.close] afterwards.
  ///
  /// [hasUnwrittenChanges] after this means the last write failed and nothing
  /// will try again: those changes stayed in the document and never reached
  /// the disk.
  Future<void> dispose() async {
    await flush();
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;

    final waiters = List.of(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      waiter.completer.completeError(_notStored(waiter.version));
    }
  }
}

/// The first read of a [CRDTDocumentPersistence]: merges the storage into the
/// document, and reports what the storage holds and what only the document
/// has.
class _Restore {
  _Restore(this._document, this._storage) : origin = Object();

  final CRDTDocument _document;
  final CRDTDocumentStorage _storage;

  /// Tags the import, so the events it publishes are not written back.
  final Object origin;

  bool _abandoned = false;

  /// Makes a read still in flight land nowhere.
  void abandon() => _abandoned = true;

  /// Reads the storage back into the document.
  ///
  /// Returns without suspending when the storage answers both reads without
  /// suspending, which is what [CRDTDocumentPersistence.openSync] rests on.
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

  /// The changes the document held before the persistence started following
  /// it.
  ///
  /// Nothing reported them: an event is built only once something listens, and
  /// the persistence subscribes when it is built. A document edited before
  /// `open` — which is the whole point of taking one as an argument — would
  /// otherwise keep those changes in memory only, while the changes written
  /// after them reach the disk naming dependencies that are not there. The
  /// next open then cannot replay them.
  ///
  /// [stored] is what the storage already holds, so a normal reopen finds
  /// nothing and pays one set of ids.
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

  /// [snapshots] from the oldest to the newest, in the order [newestSnapshot]
  /// picks them.
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

/// What [_Restore.run] found on the storage, and what only the document had.
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

  /// The version the storage brings back: its changes and its snapshots.
  final VersionVector version;

  /// The ids of the stored snapshots, from the oldest to the newest.
  final List<String> snapshotIds;

  /// The changes the document held and the storage did not.
  final List<Change> unwrittenChanges;

  /// The snapshot of the document after the restore, when the storage does not
  /// hold it; `null` otherwise.
  final Snapshot? unwrittenSnapshot;
}

class _Step {
  _Step(this.write, {this.covers});

  final FutureOr<void> Function() write;

  /// The version a snapshot step stores; `null` for the other steps.
  final VersionVector? covers;
}

class _Waiter {
  _Waiter(this.version) : completer = Completer<void>();

  final VersionVector version;

  final Completer<void> completer;
}
