import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

final _peer = PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518');

Uint8List _encode({
  int kind = 0,
  OperationId? stamp,
  List<int> body = const [1, 2, 3],
}) {
  return OperationEnvelopeCodec.encode(
    handlerType: 'H',
    handlerId: 'h1',
    kind: kind,
    stamp: stamp,
    body: Uint8List.fromList(body),
  );
}

void main() {
  group('OperationEnvelopeCodec', () {
    test('round-trips an envelope without a stamp', () {
      final envelope = OperationEnvelopeCodec.decode(_encode(kind: 2));

      expect(envelope.handlerType, equals('H'));
      expect(envelope.handlerId, equals('h1'));
      expect(envelope.kind, equals(2));
      expect(envelope.stamp, isNull);
    });

    test('round-trips an envelope with a stamp', () {
      final stamp = OperationId(_peer, HybridLogicalClock(l: 987654321, c: 12));

      final envelope = OperationEnvelopeCodec.decode(
        _encode(kind: 3, stamp: stamp),
      );

      expect(envelope.kind, equals(3));
      expect(envelope.stamp, equals(stamp));
    });

    test('the stamp costs exactly its own bytes, and one flag bit', () {
      final stamp = OperationId(_peer, HybridLogicalClock(l: 1, c: 0));
      final plain = _encode(kind: 5);
      final stamped = _encode(kind: 5, stamp: stamp);

      expect(
        stamped.length - plain.length,
        equals(OperationId.byteLength),
      );

      // The kind byte is the last one before where the stamp starts.
      final kindOffset = plain.length - 3 - 1;
      expect(plain[kindOffset], equals(5));
      expect(stamped[kindOffset], equals(5 | 0x80));
    });

    test('the body stays where the offset says, stamp or not', () {
      final stamp = OperationId(_peer, HybridLogicalClock(l: 7, c: 7));

      for (final bytes in [_encode(), _encode(stamp: stamp)]) {
        final envelope = OperationEnvelopeCodec.decode(bytes);
        expect(
          Uint8List.sublistView(bytes, envelope.bodyOffset),
          equals([1, 2, 3]),
        );
      }
    });

    test('raises on a buffer that flags a stamp and stops short of it', () {
      final stamp = OperationId(_peer, HybridLogicalClock(l: 1, c: 0));
      final full = _encode(stamp: stamp, body: const []);
      final truncated = Uint8List.sublistView(full, 0, full.length - 1);

      expect(
        () => OperationEnvelopeCodec.decode(truncated),
        throwsA(isA<FormatException>()),
      );
    });

    test('refuses a kind that would collide with the stamp flag', () {
      expect(() => _encode(kind: 128), throwsA(isA<ArgumentError>()));
      expect(() => _encode(kind: -1), throwsA(isA<ArgumentError>()));
      expect(
        OperationEnvelopeCodec.decode(
          _encode(kind: OperationType.maxKind),
        ).kind,
        equals(OperationType.maxKind),
      );
    });
  });
}
