/// One persisted opaque change blob of a relay room log.
class RelayLogEntry {
  /// Constructor
  const RelayLogEntry({
    required this.seq,
    required this.blob,
  });

  /// Sequence number assigned by the relay
  /// (monotonically increasing per room, starting at `1`)
  final int seq;

  /// The change payload (opaque base64)
  final String blob;
}

/// The latest snapshot of a relay room.
class RelaySnapshotRecord {
  /// Constructor
  const RelaySnapshotRecord({
    required this.blob,
    required this.upToSeq,
  });

  /// The snapshot payload (opaque base64)
  final String blob;

  /// The last log sequence number covered by this snapshot
  final int upToSeq;
}

/// Pluggable, CRDT-agnostic persistence for relay rooms.
///
/// A relay room persists an append-only log of opaque change blobs plus, at
/// most, one snapshot. The store never interprets the blobs: assembling them
/// into a CRDT document is entirely a client concern.
///
/// The default implementation is `InMemoryRelayStore`.
abstract class RelayStore {
  /// Appends [blobs] in order to the [roomId] log, assigning one sequence
  /// number per blob. Returns the last assigned sequence number.
  Future<int> append(String roomId, List<String> blobs);

  /// The [roomId] log entries with a sequence number greater than
  /// [afterSeq], ordered by sequence number.
  Future<List<RelayLogEntry>> readLog(String roomId, {int afterSeq = 0});

  /// The current [roomId] log length
  Future<int> logLength(String roomId);

  /// The last sequence number assigned for [roomId] (`0` if none).
  ///
  /// Monotonic: unlike [logLength] it is not decreased by [saveSnapshot].
  Future<int> lastSeq(String roomId);

  /// The latest [roomId] snapshot, if any
  Future<RelaySnapshotRecord?> getSnapshot(String roomId);

  /// Stores [snapshot] as the latest [roomId] snapshot and deletes the log
  /// entries it covers (sequence number `<=` [RelaySnapshotRecord.upToSeq]).
  Future<void> saveSnapshot(String roomId, RelaySnapshotRecord snapshot);

  /// The ids of the rooms with persisted state
  Future<Set<String>> get roomIds;

  /// Deletes every trace of [roomId]
  Future<void> deleteRoom(String roomId);
}
