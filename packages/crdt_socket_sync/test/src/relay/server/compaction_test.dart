import 'package:crdt_socket_sync/src/relay/server/compaction.dart';
import 'package:test/test.dart';

void main() {
  group('RelayCompactionCoordinator', () {
    late DateTime now;
    late RelayCompactionCoordinator coordinator;

    setUp(() {
      now = DateTime(2026);
      coordinator = RelayCompactionCoordinator(
        logCompactThreshold: 10,
        retryInterval: const Duration(seconds: 30),
        now: () => now,
      );
    });

    test('does not ask below or at the threshold', () {
      expect(coordinator.shouldCompact('room', 9), isFalse);
      expect(coordinator.shouldCompact('room', 10), isFalse);
    });

    test('asks once past the threshold, then rate limits', () {
      expect(coordinator.shouldCompact('room', 11), isTrue);

      // The next threshold crossings within the retry interval are muted:
      // only one client at a time is asked to upload.
      expect(coordinator.shouldCompact('room', 12), isFalse);
      now = now.add(const Duration(seconds: 29));
      expect(coordinator.shouldCompact('room', 13), isFalse);

      // After the retry interval the room can be asked again (the asked
      // client may have disconnected without uploading).
      now = now.add(const Duration(seconds: 1));
      expect(coordinator.shouldCompact('room', 14), isTrue);
    });

    test('reset clears the rate limit', () {
      expect(coordinator.shouldCompact('room', 11), isTrue);
      coordinator.reset('room');
      expect(coordinator.shouldCompact('room', 11), isTrue);
    });

    test('rooms are rate limited independently', () {
      expect(coordinator.shouldCompact('room-1', 11), isTrue);
      expect(coordinator.shouldCompact('room-2', 11), isTrue);
      expect(coordinator.shouldCompact('room-1', 11), isFalse);
    });
  });
}
