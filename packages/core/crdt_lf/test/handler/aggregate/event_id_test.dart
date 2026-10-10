import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

final _author = PeerId.parse('00000000-0000-4000-8000-00000000000a');

EventId _id(int l, int index) =>
    EventId(OperationId(_author, HybridLogicalClock(l: l, c: 0)), index);

void main() {
  group('EventId', () {
    test('survives a round trip through bytes', () {
      final id = _id(7, 300);

      expect(EventId.fromBytes(id.toBytes()), id);
    });

    test('reads one id after another from a larger buffer', () {
      final first = _id(1, 0);
      final second = _id(2, 5);
      final out = BytesBuilder(copy: false);
      first.writeTo(out);
      second.writeTo(out);
      final bytes = out.toBytes();

      final read = EventId.readFromBytes(bytes);
      final next = EventId.readFromBytes(bytes, offset: read.nextOffset);

      expect(read.value, first);
      expect(next.value, second);
      expect(next.nextOffset, bytes.length);
    });

    test('refuses a truncated or padded buffer', () {
      final bytes = _id(1, 0).toBytes();

      expect(
        () => EventId.fromBytes(Uint8List.sublistView(bytes, 0, 10)),
        throwsFormatException,
      );
      expect(
        () => EventId.fromBytes(Uint8List.fromList([...bytes, 0])),
        throwsFormatException,
      );
    });

    test('orders by stamp, then by place in the batch', () {
      final ids = [_id(2, 0), _id(1, 1), _id(1, 0)]..sort();

      expect(ids, [_id(1, 0), _id(1, 1), _id(2, 0)]);
    });

    test('names the peer that wrote it', () {
      expect(_id(1, 0).author, _author);
      expect(EventContext(_id(1, 0)).author, _author);
    });
  });
}
