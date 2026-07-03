import 'dart:async';

import 'package:crdt_socket_sync/src/common/outbound_queue.dart';
import 'package:test/test.dart';

void main() {
  group('OutboundQueue', () {
    test('sends messages serially, in order', () async {
      final sent = <int>[];
      final queue = OutboundQueue(
        onSend: (data) async => sent.add(data.first),
        maxBufferSize: 1000,
      );

      await Future.wait([
        queue.add([1]),
        queue.add([2]),
        queue.add([3]),
      ]);

      expect(sent, [1, 2, 3]);
    });

    test('tracks pendingBytes and drains back to zero', () async {
      final gate = Completer<void>();
      final queue = OutboundQueue(
        onSend: (_) => gate.future,
        maxBufferSize: 1000,
      );

      final future = queue.add([1, 2, 3, 4]);
      expect(queue.pendingBytes, 4);

      gate.complete();
      await future;
      expect(queue.pendingBytes, 0);
    });

    test('rejects and closes when the byte bound would be exceeded', () {
      // onSend never completes, so bytes accumulate in the queue.
      final queue = OutboundQueue(
        onSend: (_) => Completer<void>().future,
        maxBufferSize: 5,
      );

      // 3 bytes: fits (pending = 3).
      final first = queue.add([1, 2, 3]);
      expect(queue.pendingBytes, 3);

      // 3 more bytes: projected 6 > 5 -> overflow.
      expect(
        () => queue.add([4, 5, 6]),
        throwsA(isA<OutboundBufferOverflow>()),
      );
      expect(queue.isClosed, isTrue);

      // Once closed, further adds are rejected.
      expect(() => queue.add([7]), throwsStateError);

      // Silence the first (dropped) send's future.
      first.ignore();
    });

    test('a message exactly at the bound is accepted', () async {
      final sent = <List<int>>[];
      final queue = OutboundQueue(
        onSend: (data) async => sent.add(data),
        maxBufferSize: 3,
      );

      await queue.add([1, 2, 3]);
      expect(sent, [
        [1, 2, 3],
      ]);
      expect(queue.pendingBytes, 0);
    });

    test('a failing send does not stall subsequent sends', () async {
      final sent = <int>[];
      var first = true;
      final queue = OutboundQueue(
        onSend: (data) async {
          if (first) {
            first = false;
            throw Exception('boom');
          }
          sent.add(data.first);
        },
        maxBufferSize: 1000,
      );

      await queue.add([1]).catchError((_) {});
      await queue.add([2]);

      expect(sent, [2]);
    });

    test('close() drops queued messages and blocks new ones', () async {
      final gate = Completer<void>();
      final sent = <int>[];
      final queue = OutboundQueue(
        onSend: (data) async {
          await gate.future;
          sent.add(data.first);
        },
        maxBufferSize: 1000,
      );

      final first = queue.add([1]); // in-flight, waiting on gate
      final second = queue.add([2]); // queued behind first

      queue.close();
      gate.complete();

      await Future.wait([first, second]);

      // Nothing was sent after close.
      expect(sent, isEmpty);
      expect(() => queue.add([3]), throwsStateError);
    });
  });
}
