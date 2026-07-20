import 'package:crdt_socket_sync/src/relay/client/pending_queue.dart';
import 'package:test/test.dart';

void main() {
  group('RelayPendingQueue', () {
    late RelayPendingQueue queue;

    setUp(() {
      queue = RelayPendingQueue();
    });

    test('takeInFlight marks the whole queue as one window', () {
      queue
        ..add('a')
        ..add('b');

      expect(queue.takeInFlight(), ['a', 'b']);
      expect(queue.hasInFlight, isTrue);
      expect(queue.length, 2);
    });

    test('ack drops the acknowledged head', () {
      queue
        ..add('a')
        ..add('b')
        ..takeInFlight()
        // Queued while the push was in flight.
        ..add('c')
        ..ack(2);

      expect(queue.hasInFlight, isFalse);
      expect(queue.length, 1);
      expect(queue.takeInFlight(), ['c']);
    });

    test('ack is bounded by the in-flight window', () {
      queue
        ..add('a')
        ..takeInFlight()
        ..add('b')
        // A count larger than the window must not drop unpushed blobs.
        ..ack(5);

      expect(queue.length, 1);
      expect(queue.takeInFlight(), ['b']);
    });

    test('resetInFlight keeps the blobs queued for re-delivery', () {
      queue
        ..add('a')
        ..add('b')
        ..takeInFlight()
        ..resetInFlight();

      expect(queue.hasInFlight, isFalse);
      expect(queue.length, 2);
      expect(queue.takeInFlight(), ['a', 'b']);
    });

    test('ack after resetInFlight does not drop pending blobs', () {
      queue
        ..add('a')
        ..takeInFlight()
        ..resetInFlight()
        // A late ack for a push whose window was reset must be ignored.
        ..ack(1);

      expect(queue.length, 1);
    });
  });
}
