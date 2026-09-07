import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/relay/client/pending_queue.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../../utils/mock_handler.dart';
import '../../utils/mock_operation.dart';

void main() {
  group('RelayPendingQueue', () {
    late RelayPendingQueue queue;
    late CRDTDocument document;
    late MockHandler handler;

    setUp(() {
      queue = RelayPendingQueue();
      document = CRDTDocument(peerId: PeerId.generate());
      handler = MockHandler(document);
    });

    /// A change identified by [clock], so a test can name it back.
    Change change(String clock) {
      final peerId = PeerId.generate();
      return Change(
        id: OperationId(peerId, HybridLogicalClock(l: clock.hashCode, c: 1)),
        operation: MockOperation(handler),
        deps: const {},
        author: peerId,
      );
    }

    test('takeInFlight marks the whole queue as one window', () {
      final a = change('a');
      final b = change('b');
      queue
        ..add(a)
        ..add(b);

      expect(queue.takeInFlight(), [a, b]);
      expect(queue.hasInFlight, isTrue);
      expect(queue.length, 2);
    });

    test('ack drops the acknowledged head', () {
      final c = change('c');
      queue
        ..add(change('a'))
        ..add(change('b'))
        ..takeInFlight()
        // Queued while the push was in flight.
        ..add(c)
        ..ack(2);

      expect(queue.hasInFlight, isFalse);
      expect(queue.length, 1);
      expect(queue.takeInFlight(), [c]);
    });

    test('ack is bounded by the in-flight window', () {
      final b = change('b');
      queue
        ..add(change('a'))
        ..takeInFlight()
        ..add(b)
        // A count larger than the window must not drop unpushed changes.
        ..ack(5);

      expect(queue.length, 1);
      expect(queue.takeInFlight(), [b]);
    });

    test('resetInFlight keeps the changes queued for re-delivery', () {
      final a = change('a');
      final b = change('b');
      queue
        ..add(a)
        ..add(b)
        ..takeInFlight()
        ..resetInFlight();

      expect(queue.hasInFlight, isFalse);
      expect(queue.length, 2);
      expect(queue.takeInFlight(), [a, b]);
    });

    test('ack after resetInFlight does not drop pending changes', () {
      queue
        ..add(change('a'))
        ..takeInFlight()
        ..resetInFlight()
        // A late ack for a push whose window was reset must be ignored.
        ..ack(1);

      expect(queue.length, 1);
    });

    test('adding the same change twice queues it once', () {
      final a = change('a');

      queue
        ..add(a)
        ..add(a);

      expect(queue.pending, [a]);
    });

    test('a change comes back after it was acked and written again', () {
      final a = change('a');

      queue
        ..add(a)
        ..takeInFlight()
        ..ack(1)
        ..add(a);

      expect(queue.pending, [a], reason: 'the ack released the id');
    });

    test('pending is a read-only view', () {
      final a = change('a');
      queue.add(a);

      expect(queue.pending, [a]);
      expect(() => queue.pending.add(change('b')), throwsUnsupportedError);
    });
  });
}
