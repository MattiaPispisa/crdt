import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

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
/// In a synced app it is also what makes the client offline-first: the
/// document comes back after a restart, and a sync client catches its peer up
/// from the restored state.
class CRDTDocumentPersistence {
  CRDTDocumentPersistence._(
    this._document,
    this.storage,
    this._writeDelay,
    this._compactAfter,
    this._onError,
  );

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
  /// [onError] is called when a write fails. Without it a failed write is
  /// silent.
  static Future<CRDTDocumentPersistence> open(
    CRDTDocument document,
    CRDTDocumentStorage storage, {
    Duration writeDelay = const Duration(milliseconds: 250),
    int? compactAfter,
    void Function(Object error, StackTrace stack)? onError,
  }) async {
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
      onError,
    );

    // Before the restore, not after: a change applied while the storage is
    // being read would otherwise never be written down. The restore tags
    // itself, and [_onEvent] skips what carries that tag.
    persistence._subscription = document.events.listen(persistence._onEvent);

    await persistence._restore();
    return persistence;
  }

  final CRDTDocument _document;

  /// Where the document is kept.
  final CRDTDocumentStorage storage;

  final Duration _writeDelay;
  final int? _compactAfter;
  final void Function(Object error, StackTrace stack)? _onError;

  /// Tags the restore, so the events it publishes are not written back.
  final Object _restoreOrigin = Object();

  StreamSubscription<CRDTDocumentEvent>? _subscription;

  /// Changes waiting for the next write.
  final List<Change> _pending = <Change>[];

  /// How many changes the store holds, for the `compactAfter` of [open].
  int _stored = 0;

  Timer? _timer;

  /// A write already running, so two never overlap.
  Future<void> _writing = Future<void>.value();

  Future<void> _restore() async {
    final changes = await storage.changes.getChanges();
    final snapshots = await storage.snapshots.getSnapshots();
    _stored = changes.length;

    if (changes.isEmpty && snapshots.isEmpty) {
      return;
    }

    _document.import(
      snapshot: _newest(snapshots),
      changes: changes,
      merge: true,
      pruneHistory: false,
      origin: _restoreOrigin,
    );
  }

  /// The newest of [snapshots], or `null` when there is none.
  ///
  /// A snapshot holds the whole state of every handler, so one is enough.
  /// There is normally one on the store: [_writeSnapshot] drops the old one
  /// as soon as the new one is written. A process killed between those two
  /// steps leaves two — and the prune that removes the covered changes runs
  /// after that write, so every change is still stored and the older snapshot
  /// adds nothing.
  static Snapshot? _newest(List<Snapshot> snapshots) {
    if (snapshots.isEmpty) {
      return null;
    }
    return snapshots.reduce(
      (a, b) =>
          b.versionVector.isStrictlyNewerOrEqualThan(a.versionVector) ? b : a,
    );
  }

  void _onEvent(CRDTDocumentEvent event) {
    switch (event) {
      case DocumentChangesApplied():
        if (identical(event.origin, _restoreOrigin)) {
          return;
        }
        // Both sources: what this peer wrote, and what came from a peer.
        // Reopening offline has to bring back the whole document, not half.
        _pending.addAll(event.changes);
        _timer ??= Timer(_writeDelay, _flush);
      case DocumentSnapshotUpdated():
        if (identical(event.origin, _restoreOrigin)) {
          return;
        }
        _enqueue(() => _writeSnapshot(event.snapshot));
      case DocumentHistoryPruned():
        _enqueue(() => _writePrune(event.removed, event.rewritten));
    }
  }

  /// Runs [work] after whatever is already writing.
  ///
  /// The order matters: a snapshot has to reach the disk before the prune that
  /// drops the changes it covers.
  void _enqueue(Future<void> Function() work) {
    _writing = _writing.then((_) => work()).catchError(_report);
  }

  void _report(Object error, StackTrace stack) {
    _onError?.call(error, stack);
  }

  /// Writes what is waiting, now, and waits for it.
  ///
  /// Loops until a whole round produces nothing new, for two reasons.
  /// [CRDTDocument.events] hands an event to its listeners on a microtask, so
  /// the ones already published have to be let through first — otherwise
  /// flushing right after an edit would write everything except that edit. And
  /// a write can cause more work: a compaction snapshots the document, which
  /// publishes events of its own.
  ///
  /// A write made while this runs is written by it too, so a flush that races
  /// a typist takes one more round.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;

    while (true) {
      // A zero delay runs after the microtask queue, which is where a
      // published event reaches [_onEvent].
      await Future<void>.delayed(Duration.zero);
      if (_pending.isNotEmpty) {
        _enqueue(_writePending);
      }
      final tail = _writing;
      await tail;
      await Future<void>.delayed(Duration.zero);

      if (_pending.isEmpty && identical(tail, _writing)) {
        return;
      }
    }
  }

  void _flush() {
    _timer = null;
    _enqueue(_writePending);
  }

  Future<void> _writePending() async {
    if (_pending.isEmpty) {
      return;
    }
    final batch = List<Change>.of(_pending);
    _pending.clear();
    await storage.changes.saveChanges(batch);
    _stored += batch.length;
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

  /// Keeps one snapshot per document: the newest replaces the one before it.
  ///
  /// Written before the old one is dropped, never after. A process killed
  /// between the two steps would otherwise leave the document with no snapshot
  /// at all — and once the history it covers is pruned, that state has nowhere
  /// else to come from.
  Future<void> _writeSnapshot(Snapshot snapshot) async {
    final stale = (await storage.snapshots.getSnapshots())
        .map((s) => s.id)
        .where((id) => id != snapshot.id)
        .toList();

    await storage.snapshots.saveSnapshot(snapshot);
    await storage.snapshots.deleteSnapshots(stale);
  }

  /// Drops what the prune removed, and writes the survivors again.
  ///
  /// A change that pointed at a pruned dependency was rebuilt without it, so
  /// the bytes on disk describe a change that no longer exists.
  Future<void> _writePrune(List<Change> removed, List<Change> rewritten) async {
    await storage.changes.deleteChanges(removed);
    await storage.changes.saveChanges(rewritten);
    _stored = await storage.changes.count;
  }

  /// Writes what is still waiting and stops following the document.
  Future<void> dispose() async {
    await flush();
    await _subscription?.cancel();
    _subscription = null;
  }
}
