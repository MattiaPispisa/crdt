import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../helpers/pn_counter_handler.dart';

void main() {
  group('Operation', () {
    late CRDTDocument doc;
    late PNCounterHandler counter;

    setUp(() {
      doc = CRDTDocument(peerId: PeerId.generate());
      counter = PNCounterHandler(doc, 'counter');
    });

    OperationId stamp(int clock) =>
        OperationId(doc.peerId, HybridLogicalClock(l: clock, c: 0));

    group('stamp', () {
      test('starts unset and takes the first value written', () {
        final operation = PNCounterIncrementOperation(
          id: counter.id,
          type: counter.incrementType,
          delta: 1,
        );

        expect(operation.stamp, isNull);

        operation.stamp = stamp(1);
        expect(operation.stamp, equals(stamp(1)));
      });

      // The stamp ends up inside handler state, so an operation restamped
      // after one peer folded it leaves the two holding different values with
      // no error anywhere. There is no legitimate second write: local ones are
      // minted in `registerOperation`, remote ones are read off the envelope,
      // and a compound is a fresh operation.
      test('refuses a second write', () {
        final operation = PNCounterIncrementOperation(
          id: counter.id,
          type: counter.incrementType,
          delta: 1,
        )..stamp = stamp(1);

        expect(() => operation.stamp = stamp(2), throwsStateError);
        expect(() => operation.stamp = null, throwsStateError);
        expect(operation.stamp, equals(stamp(1)));
      });

      test('an operation the document minted refuses to be restamped', () {
        counter.increment(2);

        final operation = counter.operations().single;
        expect(operation.stamp, isNull, reason: 'increment is not stamped');

        // Nothing stops the first write on an unstamped kind, but the frame it
        // produces is refused on decode by the handler that reads it.
        operation.stamp = stamp(1);
        expect(() => operation.stamp = stamp(2), throwsStateError);
      });
    });
  });
}
