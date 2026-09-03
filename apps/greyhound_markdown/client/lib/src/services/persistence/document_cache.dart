import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_socket_sync/relay_client.dart';
import 'package:hive/hive.dart';

/// A room's document kept on disk, so reopening it offline does not start from
/// an empty page.
///
/// It reads the room back at [open], then follows [CRDTDocument.events] and
/// writes down what each event reports. Nothing is ever exported again: the
/// document says what moved, and only that is written.
///
/// It also keeps the relay outbox — the changes this device wrote that the
/// relay has not acknowledged. Delivery is at-least-once for as long as the
/// client lives; writing the outbox down is what carries it across a reload.
///
/// Every room gets its own Hive boxes, named after its id. On the web that is
/// IndexedDB.
class DocumentCache {
  DocumentCache._(this._document, this._client, this._storage, this._outbox);

  /// Opens the cache of [document], loads what a previous session left, hands
  /// [client] back its unsent changes, and starts following the document.
  ///
  /// Call before connecting: nothing is pushed until the relay says hello, so
  /// the restored outbox goes out with everything else.
  ///
  /// The saved state is merged rather than imported: on a reopen the document
  /// may already hold changes of this session, and history is kept because the
  /// relay can ask this client for a snapshot covering it.
  static Future<DocumentCache> open(
    CRDTDocument document,
    RelaySocketClient client,
  ) async {
    final storage = await CRDTHive.openStorageForDocument(document.documentId);
    final outbox = await Hive.openBox<String>(_outboxName(document.documentId));

    final changes = storage.changes.getChanges();
    // Normally one snapshot, but a write interrupted halfway can leave two.
    // Both describe the same room, so folding them loses nothing.
    final snapshots = storage.snapshots.getSnapshots();

    document.import(
      snapshot: snapshots.isEmpty
          ? null
          : snapshots.reduce((a, b) => a.merged(b)),
      changes: changes,
      merge: true,
      pruneHistory: false,
    );

    // A restored change reaches the document as an imported one, never as a
    // local one, so `localChanges` will not push it. Without this, anything
    // written offline stays on this device for good.
    final unsent = outbox.keys.cast<String>().toSet();
    if (unsent.isNotEmpty) {
      client.restorePendingChanges(
        changes
            .where((change) => unsent.contains(change.id.toString()))
            .toList()
            .sorted(),
      );
    }

    return DocumentCache._(document, client, storage, outbox).._listen();
  }

  static String _outboxName(String documentId) => 'relay_outbox_$documentId';

  final CRDTDocument _document;
  final RelaySocketClient _client;
  final CRDTDocumentStorage _storage;
  final Box<String> _outbox;

  StreamSubscription<CRDTDocumentEvent>? _subscription;

  /// Changes waiting for the next write.
  final List<Change> _pending = <Change>[];

  Timer? _timer;

  /// How long a change waits for the ones after it.
  ///
  /// One keystroke is one transaction, so writing on every event would put a
  /// round-trip to IndexedDB between the typist and the next character. A
  /// quarter of a second is short enough that a reload right after typing
  /// loses nothing a person would notice.
  static const Duration _writeDelay = Duration(milliseconds: 250);

  void _listen() {
    _subscription = _document.events.listen((event) {
      switch (event) {
        case DocumentChangesApplied():
          // Both sources: what this peer wrote, and what came from the relay.
          // Reopening offline has to bring back the whole room, not half of it.
          _pending.addAll(event.changes);
          _timer ??= Timer(_writeDelay, _flush);
        case DocumentSnapshotUpdated():
          // The relay compacts a busy room: past that point the log alone no
          // longer describes the state, so the snapshot has to be kept.
          unawaited(_writeSnapshot(event.snapshot));
        case DocumentHistoryPruned():
          // Nothing prunes here — the relay client always passes
          // `pruneHistory: false`. Kept so a future prune is not lost quietly.
          unawaited(_storage.changes.deleteChanges(event.removed));
          unawaited(_storage.changes.saveChanges(event.rewritten));
      }
    });
  }

  Future<void> _flush() async {
    _timer = null;
    await _writePending();
    await _writeOutbox();
  }

  Future<void> _writePending() async {
    if (_pending.isEmpty) {
      return;
    }
    final batch = List<Change>.of(_pending);
    _pending.clear();
    await _storage.changes.saveChanges(batch);
  }

  /// Mirrors the ids the relay still owes an ack for.
  ///
  /// Written by difference rather than rewritten whole: a tab closed between a
  /// clear and a put would otherwise lose the outbox entirely.
  ///
  /// It rides the same timer as the changes, so an ack that arrives while
  /// nothing else happens is not written until the next edit. That leaves ids
  /// of already-delivered changes behind, and a later restore pushes them
  /// again — which the relay appends and every peer discards as known.
  /// Re-delivery is the cost this queue is designed to pay.
  Future<void> _writeOutbox() async {
    final current = {
      for (final change in _client.pendingChanges) change.id.toString(),
    };
    final stored = _outbox.keys.cast<String>().toSet();

    final added = current.difference(stored);
    final delivered = stored.difference(current);

    if (added.isNotEmpty) {
      await _outbox.putAll({for (final id in added) id: id});
    }
    if (delivered.isNotEmpty) {
      await _outbox.deleteAll(delivered);
    }
  }

  /// Keeps one snapshot per room: the newest replaces the one before it.
  ///
  /// Written before the old one is dropped, never after. A tab closed between
  /// the two steps would otherwise leave the room with no snapshot at all —
  /// and once the relay has compacted, the history it covers reaches this
  /// client only inside a snapshot, never as changes in the log.
  Future<void> _writeSnapshot(Snapshot snapshot) async {
    final stale = _storage.snapshots
        .getSnapshots()
        .map((s) => s.id)
        .where((id) => id != snapshot.id)
        .toList();

    await _storage.snapshots.saveSnapshot(snapshot);
    await _storage.snapshots.deleteSnapshots(stale);
  }

  /// Writes what is still waiting and stops following the document.
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _flush();
  }
}
