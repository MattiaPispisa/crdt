import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

void main() {
  group('ORHandlerTag', () {
    test('should create a tag from a string', () {
      final tag =
          ORHandlerTag.parse('ba5f766a-fd29-4e1c-9a1f-f9d53ce6bc7f@12.0');
      expect(
        tag.hlc,
        isA<HybridLogicalClock>()
            .having((hlc) => hlc.l, 'logical time', equals(12))
            .having((hlc) => hlc.c, 'counter', equals(0)),
      );
      expect(
        tag.peerId,
        isA<PeerId>().having(
          (peerId) => peerId.toString(),
          'peer id',
          equals('ba5f766a-fd29-4e1c-9a1f-f9d53ce6bc7f'),
        ),
      );
    });

    test('should toString correctly', () {
      final tag = ORHandlerTag(
        hlc: HybridLogicalClock(l: 12, c: 0),
        peerId: PeerId.parse('c0ae4572-2525-4e9d-89ae-3058f0dde1ee'),
      );
      expect(
        tag.toString(),
        equals('c0ae4572-2525-4e9d-89ae-3058f0dde1ee@12.0'),
      );
    });

    test('should throw FormatException on invalid format', () {
      expect(
        () => ORHandlerTag.parse(
          'ba5f766a-fd29-4e1c-9a1f-f9d53ce6bc7f@12.0@13.0',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('should compare correctly', () {
      final tag1 = ORHandlerTag(
        hlc: HybridLogicalClock(l: 12, c: 0),
        peerId: PeerId.parse('c0ae4572-2525-4e9d-89ae-3058f0dde1ee'),
      );
      final tag2 = ORHandlerTag(
        hlc: HybridLogicalClock(l: 12, c: 0),
        peerId: PeerId.parse('c0ae4572-2525-4e9d-89ae-3058f0dde1ee'),
      );
      expect(tag1, equals(tag2));
      expect(tag1.hashCode, equals(tag2.hashCode));
      expect(tag1.compareTo(tag2), equals(0));
    });
  });
}
