import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

/// Pinned in ascending order, so a tie-break has a known winner.
final _peerA = PeerId.parse('00000000-0000-4000-8000-00000000000a');
final _peerB = PeerId.parse('00000000-0000-4000-8000-00000000000b');

OperationStamp _stamp(PeerId peer, int l, int c) =>
    OperationStamp(hlc: HybridLogicalClock(l: l, c: c), peerId: peer);

void main() {
  group('OperationStamp', () {
    group('ordering', () {
      test('the clock decides when the clocks differ', () {
        // The higher clock wins even though its peer sorts lower.
        expect(_stamp(_peerA, 2, 0).compareTo(_stamp(_peerB, 1, 0)),
            greaterThan(0));
        expect(_stamp(_peerA, 1, 1).compareTo(_stamp(_peerA, 1, 0)),
            greaterThan(0));
      });

      test('the peer settles two stamps that share a clock', () {
        final a = _stamp(_peerA, 5, 3);
        final b = _stamp(_peerB, 5, 3);

        expect(a.compareTo(b), lessThan(0));
        expect(b.compareTo(a), greaterThan(0));
      });

      test('a stamp equals itself', () {
        expect(_stamp(_peerA, 5, 3).compareTo(_stamp(_peerA, 5, 3)), equals(0));
      });

      test('sorts into one order whatever order it is given', () {
        final stamps = [
          _stamp(_peerB, 5, 3),
          _stamp(_peerA, 5, 3),
          _stamp(_peerA, 5, 4),
          _stamp(_peerB, 4, 9),
        ];

        final ascending = [...stamps]..sort();
        final fromReversed = [...stamps.reversed]..sort();

        expect(fromReversed, equals(ascending));
        expect(ascending.first, equals(_stamp(_peerB, 4, 9)));
        expect(ascending.last, equals(_stamp(_peerA, 5, 4)));
      });
    });

    group('identity', () {
      test('two stamps with the same clock and peer are one value', () {
        expect(_stamp(_peerA, 5, 3), equals(_stamp(_peerA, 5, 3)));
        expect(
          _stamp(_peerA, 5, 3).hashCode,
          equals(_stamp(_peerA, 5, 3).hashCode),
        );
      });

      test('the peer is part of the identity', () {
        // The OR handlers keep stamps in sets, so this is what stops two
        // peers writing in the same tick from tombstoning each other.
        final tags = {_stamp(_peerA, 5, 3), _stamp(_peerB, 5, 3)};
        expect(tags, hasLength(2));
      });

      test('reads as peer@clock', () {
        expect(_stamp(_peerA, 5, 3).toString(), equals('$_peerA@5.3'));
      });
    });

    group('bytes', () {
      test('round-trips through a fixed 24-byte record', () {
        final stamp = _stamp(_peerA, 123456, 7);
        final bytes = stamp.toUint8List();

        expect(bytes, hasLength(OperationStamp.byteLength));
        expect(OperationStamp.byteLength, equals(24));
        expect(OperationStamp.fromUint8List(bytes), equals(stamp));
      });

      test('reads from an offset inside a larger buffer', () {
        final stamp = _stamp(_peerB, 42, 1);
        final buffer = Uint8List(OperationStamp.byteLength + 3)
          ..setRange(3, OperationStamp.byteLength + 3, stamp.toUint8List());

        expect(
          OperationStamp.fromUint8List(buffer, offset: 3),
          equals(stamp),
        );
      });

      test('refuses a buffer that stops inside the record', () {
        final short = Uint8List.sublistView(
          _stamp(_peerA, 1, 1).toUint8List(),
          0,
          OperationStamp.byteLength - 1,
        );

        expect(
          () => OperationStamp.fromUint8List(short),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });
}
