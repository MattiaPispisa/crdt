import 'package:crdt_socket_sync/src/relay/server/store.dart';

/// In-memory [RelayStore] implementation.
///
/// Room state lives only for the lifetime of the process: a relay backed by
/// this store starts empty on every restart and re-fills from the connected
/// clients (each client re-pushes its whole document state on re-sync).
class InMemoryRelayStore implements RelayStore {
  final Map<String, _RelayRoom> _rooms = {};

  _RelayRoom _room(String roomId) {
    return _rooms.putIfAbsent(roomId, _RelayRoom.new);
  }

  @override
  Future<int> append(String roomId, List<String> blobs) async {
    final room = _room(roomId);
    for (final blob in blobs) {
      room.lastSeq += 1;
      room.log.add(RelayLogEntry(seq: room.lastSeq, blob: blob));
    }
    return room.lastSeq;
  }

  @override
  Future<List<RelayLogEntry>> readLog(
    String roomId, {
    int afterSeq = 0,
  }) async {
    final room = _rooms[roomId];
    if (room == null) {
      return const [];
    }
    return room.log.where((entry) => entry.seq > afterSeq).toList();
  }

  @override
  Future<int> logLength(String roomId) async {
    return _rooms[roomId]?.log.length ?? 0;
  }

  @override
  Future<int> lastSeq(String roomId) async {
    return _rooms[roomId]?.lastSeq ?? 0;
  }

  @override
  Future<RelaySnapshotRecord?> getSnapshot(String roomId) async {
    return _rooms[roomId]?.snapshot;
  }

  @override
  Future<void> saveSnapshot(
    String roomId,
    RelaySnapshotRecord snapshot,
  ) async {
    final room = _room(roomId)..snapshot = snapshot;
    room.log.removeWhere((entry) => entry.seq <= snapshot.upToSeq);
  }

  @override
  Future<Set<String>> get roomIds async => _rooms.keys.toSet();

  @override
  Future<void> deleteRoom(String roomId) async {
    _rooms.remove(roomId);
  }
}

class _RelayRoom {
  final List<RelayLogEntry> log = [];
  int lastSeq = 0;
  RelaySnapshotRecord? snapshot;
}
