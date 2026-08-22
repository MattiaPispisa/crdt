import 'package:crdt_socket_sync/src/plugins/awareness/client/throttle.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  group('Throttler', () {
    const window = Duration(milliseconds: 50);

    test('fires the first (leading) call immediately', () {
      fakeAsync((async) {
        final throttler = Throttler(window);
        final calls = <int>[];

        throttler(() => calls.add(1));

        expect(calls, [1]);
        throttler.dispose();
      });
    });

    test('coalesces a burst and fires the latest on the trailing edge', () {
      fakeAsync((async) {
        final throttler = Throttler(window);
        final calls = <String>[];

        throttler(() => calls.add('a')); // leading, fires now
        throttler(() => calls.add('b')); // coalesced
        throttler(() => calls.add('c')); // coalesced, latest wins

        // Only the leading call has fired so far.
        expect(calls, ['a']);

        async.elapse(window);

        // Regression: the trailing call used to be dropped entirely.
        expect(calls, ['a', 'c']);
        throttler.dispose();
      });
    });

    test('no trailing fire when the window passes with no further calls', () {
      fakeAsync((async) {
        final throttler = Throttler(window);
        final calls = <int>[];

        throttler(() => calls.add(1));
        async.elapse(window + const Duration(milliseconds: 10));
        expect(calls, [1]);

        // A call after the window is a fresh leading edge.
        throttler(() => calls.add(2));
        expect(calls, [1, 2]);
        throttler.dispose();
      });
    });

    test('dispose cancels a pending trailing call', () {
      fakeAsync((async) {
        final throttler = Throttler(window);
        final calls = <int>[];

        throttler(() => calls.add(1)); // leading
        throttler(() => calls.add(2)); // pending trailing
        throttler.dispose();

        async.elapse(window * 2);
        expect(calls, [1]);
      });
    });
  });
}
