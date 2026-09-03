import 'package:crdt_lf/crdt_lf.dart';

/// One move of the durable state of a [CRDTDocument]: the changes it holds and
/// the snapshot they are replayed on top of.
///
/// A consumer that mirrors a document — a persistence adapter, a log — follows
/// [CRDTDocument.events] and writes down what each event reports, instead of
/// exporting the whole document again to find out what moved.
///
/// Events are handed out once the document is settled, so a listener always
/// reads a document that holds nothing half-applied.
sealed class CRDTDocumentEvent {
  /// Creates an event.
  const CRDTDocumentEvent();
}

/// Where a batch of [Change]s came from.
enum ChangeSource {
  /// The document wrote them itself, through a handler operation or
  /// [CRDTDocument.createChange].
  created,

  /// The document took them in from somewhere else, through
  /// [CRDTDocument.applyChange] or [CRDTDocument.importChanges].
  ingested,
}

/// [changes] entered the document's change store.
final class DocumentChangesApplied extends CRDTDocumentEvent {
  /// Creates the event that reports [changes].
  const DocumentChangesApplied({
    required this.changes,
    required this.source,
    this.origin,
  });

  /// The changes, in the order the document applied them. Never empty.
  ///
  /// Every change here is new to the document: one that was already in the
  /// store is not reported again.
  final List<Change> changes;

  /// Whether the document wrote these changes or took them in.
  ///
  /// **Not the same question as `Change.author`.** The author says which peer
  /// wrote a change, which stays true when a persistence adapter loads it back
  /// years later. This says how the change reached the document just now.
  final ChangeSource source;

  /// {@macro delta_origin}
  final Object? origin;

  @override
  String toString() => 'DocumentChangesApplied(source: $source, '
      'changes: ${changes.length}, origin: $origin)';
}

/// Why the document's snapshot was replaced.
enum SnapshotReason {
  /// The document snapshotted itself, through [CRDTDocument.takeSnapshot].
  taken,

  /// A newer snapshot replaced the current one, through
  /// [CRDTDocument.importSnapshot].
  imported,

  /// A snapshot was folded into the current one, through
  /// [CRDTDocument.mergeSnapshot].
  merged,
}

/// The document's snapshot is now [snapshot].
///
/// It always arrives **before** the [DocumentHistoryPruned] its own version
/// causes, so a consumer that writes on every event stores the snapshot before
/// dropping the changes it covers.
final class DocumentSnapshotUpdated extends CRDTDocumentEvent {
  /// Creates the event that reports [snapshot].
  const DocumentSnapshotUpdated({
    required this.snapshot,
    required this.reason,
  });

  /// The snapshot the document now holds.
  ///
  /// On [SnapshotReason.merged] this is the merged result, not the snapshot
  /// that was handed to [CRDTDocument.mergeSnapshot].
  final Snapshot snapshot;

  /// Which call replaced the snapshot.
  final SnapshotReason reason;

  @override
  String toString() =>
      'DocumentSnapshotUpdated(reason: $reason, snapshot: ${snapshot.id})';
}

/// History was pruned: the changes covered by [upTo] left the store.
final class DocumentHistoryPruned extends CRDTDocumentEvent {
  /// Creates the event that reports a prune.
  const DocumentHistoryPruned({
    required this.upTo,
    required this.removed,
    required this.rewritten,
  });

  /// The version every removed change is covered by.
  final VersionVector upTo;

  /// The changes that left the store. Never empty.
  final List<Change> removed;

  /// The changes that stayed, with their dependencies on [removed] dropped.
  ///
  /// A pruned dependency cannot be named any more, so a change that pointed at
  /// one is rebuilt without it. Bytes written down before the prune describe a
  /// change that no longer exists: write these again, or a reload replays a
  /// dependency the document cannot resolve.
  final List<Change> rewritten;

  @override
  String toString() => 'DocumentHistoryPruned(removed: ${removed.length}, '
      'rewritten: ${rewritten.length})';
}
