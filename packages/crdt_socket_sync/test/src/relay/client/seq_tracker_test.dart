import 'package:crdt_socket_sync/src/relay/client/seq_tracker.dart';
import 'package:test/test.dart';

void main() {
  group('RelaySeqTracker', () {
    late RelaySeqTracker tracker;

    setUp(() {
      tracker = RelaySeqTracker();
    });

    test('markThrough advances the contiguous prefix', () {
      tracker.markThrough(5);
      expect(tracker.maxContiguous, 5);

      // Never goes backwards.
      tracker.markThrough(3);
      expect(tracker.maxContiguous, 5);
    });

    test('contiguous ranges extend the prefix', () {
      tracker
        ..markThrough(2)
        ..addRange(from: 2, to: 4)
        ..addRange(from: 4, to: 5);
      expect(tracker.maxContiguous, 5);
    });

    test('a detached range does not advance the prefix until the hole closes',
        () {
      tracker
        ..markThrough(2)
        // Sequences 5-6 arrived, but 3-4 are still in flight elsewhere.
        ..addRange(from: 4, to: 6);
      expect(tracker.maxContiguous, 2);

      tracker.addRange(from: 2, to: 4);
      expect(tracker.maxContiguous, 6);
    });

    test('multiple detached ranges are absorbed in any order', () {
      tracker
        ..addRange(from: 4, to: 6)
        ..addRange(from: 8, to: 9)
        ..addRange(from: 6, to: 8);
      expect(tracker.maxContiguous, 0);

      tracker.markThrough(4);
      expect(tracker.maxContiguous, 9);
    });
  });
}
