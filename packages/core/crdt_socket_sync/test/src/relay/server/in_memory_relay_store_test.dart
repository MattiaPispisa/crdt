import 'package:crdt_socket_sync/src/relay/server/in_memory_relay_store.dart';
import 'package:crdt_socket_sync/src/relay/server/store.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryRelayStore', () {
    late InMemoryRelayStore store;

    setUp(() {
      store = InMemoryRelayStore();
    });

    test('append assigns monotonic sequence numbers across calls', () async {
      expect(await store.append('room', ['a', 'b']), 2);
      expect(await store.append('room', ['c']), 3);

      final log = await store.readLog('room');
      expect(log.map((e) => e.seq), [1, 2, 3]);
      expect(log.map((e) => e.blob), ['a', 'b', 'c']);
      expect(await store.lastSeq('room'), 3);
      expect(await store.logLength('room'), 3);
    });

    test('readLog filters by afterSeq', () async {
      await store.append('room', ['a', 'b', 'c']);

      final log = await store.readLog('room', afterSeq: 2);
      expect(log.map((e) => e.blob), ['c']);
    });

    test('an unknown room is empty', () async {
      expect(await store.readLog('missing'), isEmpty);
      expect(await store.logLength('missing'), 0);
      expect(await store.lastSeq('missing'), 0);
      expect(await store.getSnapshot('missing'), isNull);
    });

    test('saveSnapshot truncates the covered log but keeps lastSeq', () async {
      await store.append('room', ['a', 'b', 'c']);
      await store.saveSnapshot(
        'room',
        const RelaySnapshotRecord(blob: 'snap', upToSeq: 2),
      );

      final snapshot = await store.getSnapshot('room');
      expect(snapshot!.blob, 'snap');
      expect(snapshot.upToSeq, 2);

      final log = await store.readLog('room');
      expect(log.map((e) => e.blob), ['c']);
      expect(await store.logLength('room'), 1);

      // seq keeps growing from where it was, so a welcome built from
      // snapshot + remaining log stays consistent.
      expect(await store.append('room', ['d']), 4);
    });

    test('rooms are isolated', () async {
      await store.append('room-1', ['a']);
      await store.append('room-2', ['b', 'c']);

      expect(await store.lastSeq('room-1'), 1);
      expect(await store.lastSeq('room-2'), 2);
      expect(await store.roomIds, {'room-1', 'room-2'});

      await store.deleteRoom('room-1');
      expect(await store.roomIds, {'room-2'});
      expect(await store.readLog('room-1'), isEmpty);
    });
  });
}
