import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

void main() {
  final author = PeerId.parse('00000000-0000-4000-8000-000000000001');
  final changeId = OperationId(author, HybridLogicalClock(l: 1, c: 0));

  group('HandlerDelta', () {
    test('carries the change it came from', () {
      final event = HandlerDelta<SequenceDelta<String>>(
        delta: SequenceDelta<String>([seqInsertText('a')]),
        changeId: changeId,
        author: author,
        local: true,
        seq: 7,
      );

      expect(event.seq, 7);
      expect(event.changeId, changeId);
      expect(event.author, author);
      expect(event.local, isTrue);
    });

    test('the description names the sequence number and the delta', () {
      final event = HandlerDelta<SequenceDelta<String>>(
        delta: SequenceDelta<String>([seqInsertText('a')]),
        changeId: changeId,
        author: author,
        local: true,
        seq: 7,
      );

      expect(event.toString(), contains('seq: 7'));
      expect(event.toString(), contains('local: true'));
      expect(event.toString(), contains('SeqInsert'));
    });
  });

  group('HandlerReset', () {
    test('the description names the sequence number and the cause', () {
      const event = HandlerReset<SequenceDelta<String>>(
        cause: ResetCause.cacheDropped,
        seq: 3,
      );

      expect(event.seq, 3);
      expect(event.cause, ResetCause.cacheDropped);
      expect(
          event.toString(),
          'HandlerReset(seq: 3, cause: '
          'ResetCause.cacheDropped)');
    });
  });

  group('DeltaSyncPoint', () {
    test('the description names the point the value reflects', () {
      const point = DeltaSyncPoint<String>(value: 'hello', seq: 4);

      expect(point.value, 'hello');
      expect(point.seq, 4);
      expect(point.toString(), 'DeltaSyncPoint(seq: 4, value: hello)');
    });
  });
}
