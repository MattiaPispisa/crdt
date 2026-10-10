import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

EventContext _context(int index) => EventContext(
      EventId(
        OperationId(
          PeerId.parse('00000000-0000-4000-8000-00000000000a'),
          HybridLogicalClock(l: 1, c: 0),
        ),
        index,
      ),
    );

void main() {
  group('AggregateDelta', () {
    test('apply answers the current state', () {
      final delta = AggregateDelta<String, String>(
        previous: 'old',
        current: 'new',
        events: [AggregateEvent('rename', _context(0))],
      );

      expect(delta.apply('old'), 'new');
    });

    test('events that leave the state equal move nothing', () {
      final delta = AggregateDelta<String, String>(
        previous: 'same',
        current: 'same',
        events: [AggregateEvent('no-op', _context(0))],
      );

      expect(delta.isEmpty, isTrue);
      expect(delta.isNotEmpty, isFalse);
    });

    test('compose keeps the two ends and every event in order', () {
      final first = AggregateEvent('a', _context(0));
      final second = AggregateEvent('b', _context(1));
      final composed = AggregateDelta<String, String>(
        previous: 'one',
        current: 'two',
        events: [first],
      ).compose(
        AggregateDelta<String, String>(
          previous: 'two',
          current: 'three',
          events: [second],
        ),
      );

      expect(composed.previous, 'one');
      expect(composed.current, 'three');
      expect(composed.events, [first, second]);
    });
  });

  group('AggregateEvent', () {
    test('two events are equal when event and context are', () {
      expect(
        AggregateEvent('a', _context(0)),
        AggregateEvent('a', _context(0)),
      );
      expect(
        AggregateEvent('a', _context(0)),
        isNot(AggregateEvent('a', _context(1))),
      );
    });
  });
}
