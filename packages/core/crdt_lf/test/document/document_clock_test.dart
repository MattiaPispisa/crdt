import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/document/document_clock.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

void main() {
  group('DocumentClock', () {
    late PeerId peer;
    late DocumentClock clock;

    // An hour ahead of the wall clock, so only `receive` or `advancePast` can
    // bring the clock past it.
    HybridLogicalClock ahead({int counter = 0}) => HybridLogicalClock(
          l: DateTime.now().millisecondsSinceEpoch + 3600000,
          c: counter,
        );

    setUp(() {
      peer = PeerId.generate();
      clock = DocumentClock(peer);
    });

    test('mints ids of its peer, each newer than the one before', () {
      final first = clock.mint();
      final second = clock.mint();

      expect(first.peerId, peer);
      expect(first.hlc.happenedBefore(second.hlc), isTrue);
      expect(clock.now, second.hlc);
    });

    test('mints at the physical time it is given', () {
      expect(clock.mint(physicalTime: 1000).hlc.l, 1000);
    });

    test('mints past a time it received', () {
      final remote = ahead(counter: 7);

      clock.receive(remote);

      expect(remote.happenedBefore(clock.mint().hlc), isTrue);
    });

    test('mints past every entry of a version vector', () {
      final far = ahead(counter: 3);
      final near = HybridLogicalClock(l: 1, c: 1);

      clock.advancePast(
        VersionVector({PeerId.generate(): near, PeerId.generate(): far}),
      );

      expect(far.happenedBefore(clock.mint().hlc), isTrue);
    });
  });
}
