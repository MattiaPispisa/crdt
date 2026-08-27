import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

Uint8List _encode({
  int kind = 0,
  bool stamped = false,
  List<int> body = const [1, 2, 3],
}) {
  return OperationEnvelopeCodec.encode(
    handlerType: 'H',
    handlerId: 'h1',
    kind: kind,
    stamped: stamped,
    body: Uint8List.fromList(body),
  );
}

void main() {
  group('OperationEnvelopeCodec', () {
    test('round-trips an unstamped envelope', () {
      final envelope = OperationEnvelopeCodec.decode(_encode(kind: 2));

      expect(envelope.handlerType, equals('H'));
      expect(envelope.handlerId, equals('h1'));
      expect(envelope.kind, equals(2));
      expect(envelope.stamped, isFalse);
    });

    test('round-trips a stamped envelope, kind and flag apart', () {
      final envelope = OperationEnvelopeCodec.decode(
        _encode(kind: 3, stamped: true),
      );

      expect(envelope.kind, equals(3));
      expect(envelope.stamped, isTrue);
    });

    // The whole point of moving the stamp onto the change id: declaring a kind
    // stamped costs one bit inside a byte that was already there.
    test('the declaration costs no bytes at all', () {
      final plain = _encode(kind: 5);
      final stamped = _encode(kind: 5, stamped: true);

      expect(stamped.length, equals(plain.length));

      final kindOffset = plain.length - 3 - 1;
      expect(plain[kindOffset], equals(5));
      expect(stamped[kindOffset], equals(5 | 0x80));
    });

    test('the body stays where the offset says, flagged or not', () {
      for (final bytes in [_encode(), _encode(stamped: true)]) {
        final envelope = OperationEnvelopeCodec.decode(bytes);
        expect(
          Uint8List.sublistView(bytes, envelope.bodyOffset),
          equals([1, 2, 3]),
        );
      }
    });

    test('raises on a buffer that stops before the kind byte', () {
      final full = _encode(body: const []);
      final truncated = Uint8List.sublistView(full, 0, full.length - 1);

      expect(
        () => OperationEnvelopeCodec.decode(truncated),
        throwsA(isA<FormatException>()),
      );
    });

    test('refuses a kind that would collide with the stamped flag', () {
      expect(() => _encode(kind: 128), throwsA(isA<ArgumentError>()));
      expect(() => _encode(kind: -1), throwsA(isA<ArgumentError>()));
      expect(
        OperationEnvelopeCodec.decode(
          _encode(kind: OperationType.maxKind),
        ).kind,
        equals(OperationType.maxKind),
      );
    });

    // A kind at the ceiling sets every bit the flag does not, so a decoder
    // that masked wrongly would read it as stamped, or lose the flag.
    test('the flag and the highest kind do not bleed into each other', () {
      final envelope = OperationEnvelopeCodec.decode(
        _encode(kind: OperationType.maxKind, stamped: true),
      );

      expect(envelope.kind, equals(OperationType.maxKind));
      expect(envelope.stamped, isTrue);
    });

    // A handler decides a change is its own by comparing this prefix against
    // the head of the payload, without decoding it. If [encode] ever stopped
    // starting with these exact bytes, that check would silently match
    // nothing and handlers would stop seeing their own changes.
    test('writeEnvelopePrefix produces the head of an encoded envelope', () {
      final out = BytesBuilder(copy: false);
      OperationEnvelopeCodec.writeEnvelopePrefix(out, 'H', 'h1');
      final prefix = out.toBytes();

      expect(_encode().take(prefix.length), orderedEquals(prefix));
    });
  });
}
