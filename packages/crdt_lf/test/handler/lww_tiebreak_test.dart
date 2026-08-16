import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

/// Pinned in ascending order: the peer is the tie-break, so the winner has to
/// be known in advance for the assertions to mean anything.
const _peerA = '00000000-0000-4000-8000-00000000000a';
const _peerB = '00000000-0000-4000-8000-00000000000b';

/// Far past any wall clock this test will ever see, and still inside the 48
/// bits the encoded clock gives `l` — past that it silently wraps on the wire.
const _farFuture = 1 << 45;

/// A document whose clock only ever moves in its logical part.
///
/// `localEvent` keeps `l` and bumps `c` while `l` is ahead of the wall clock,
/// so two documents seeded this way walk the same sequence step for step.
/// That turns "two peers wrote in the same tick" from a race that shows up
/// once a year in production into a case a test can set up on purpose.
CRDTDocument _doc(String peerId) => CRDTDocument(
      peerId: PeerId.parse(peerId),
      initialClock: HybridLogicalClock(l: _farFuture, c: 0),
    );

/// Brings two clocks level, so the next local operation on each mints the
/// same HLC and only the peer can settle the winner.
void _levelClocks(CRDTDocument a, CRDTDocument b) {
  while (a.hlc.compareTo(b.hlc) < 0) {
    a.prepareMutation();
  }
  while (b.hlc.compareTo(a.hlc) < 0) {
    b.prepareMutation();
  }
}

/// Fails the test if the setup did not actually produce a tie, so a broken
/// set-up cannot quietly turn these into tests of nothing.
void _expectTie(Operation a, Operation b) {
  expect(
    a.stamp!.hlc.compareTo(b.stamp!.hlc),
    equals(0),
    reason: 'the two writes must share a clock for this to test a tie-break',
  );
  expect(a.stamp!.peerId, isNot(equals(b.stamp!.peerId)));
  expect(a.stamp!.compareTo(b.stamp!), lessThan(0));
}

void main() {
  group('two writes that share a clock', () {
    test('or_map keeps the value of the higher peer, in both orders', () {
      final a = _doc(_peerA);
      final b = _doc(_peerB);
      final mapA = CRDTORMapHandler<String, String>(a, 'm')..put('k', 'from A');
      final mapB = CRDTORMapHandler<String, String>(b, 'm')..put('k', 'from B');

      _expectTie(mapA.operations().single, mapB.operations().single);

      a.importChanges(b.exportChanges());
      b.importChanges(a.exportChanges());

      expect(mapA.value['k'], equals(mapB.value['k']));
      expect(mapA.value['k'], equals('from B'));
    });

    test('or_set keeps two tags, so one removal does not take both', () {
      final a = _doc(_peerA);
      final b = _doc(_peerB);
      final setA = CRDTORSetHandler<String>(a, 's')..add('x');
      final setB = CRDTORSetHandler<String>(b, 's')..add('x');

      _expectTie(setA.operations().single, setB.operations().single);

      // A removes what it has observed, which is its own tag alone. If the
      // peer were not part of the tag, this would tombstone B's add too.
      setA.remove('x');
      a.importChanges(b.exportChanges());
      b.importChanges(a.exportChanges());

      expect(setA.value, contains('x'));
      expect(setB.value, equals(setA.value));
    });

    // Before the stamp, the movable list compared bare clocks with
    // `happenedAfter`, which is false in both directions on a tie: nobody won,
    // the value already in place stayed, and which one that was depended on
    // the order the changes arrived in. Two peers, two results.
    test('a movable list update converges instead of going by arrival', () {
      final a = _doc(_peerA);
      final b = _doc(_peerB);
      final listA = CRDTFugueMovableListHandler<String>(a, 'l')..insert(0, 'x');
      final listB = CRDTFugueMovableListHandler<String>(b, 'l');
      b.importChanges(a.exportChanges());
      expect(listB.value, equals(['x']));

      _levelClocks(a, b);
      listA.update(0, 'from A');
      listB.update(0, 'from B');

      _expectTie(listA.operations().last, listB.operations().last);

      a.importChanges(b.exportChanges());
      b.importChanges(a.exportChanges());

      expect(listA.value, equals(listB.value));
      expect(listA.value, equals(['from B']));
    });

    test('a movable list move converges instead of going by arrival', () {
      final a = _doc(_peerA);
      final b = _doc(_peerB);
      final listA = CRDTFugueMovableListHandler<String>(a, 'l')
        ..insert(0, 'x')
        ..insert(1, 'y')
        ..insert(2, 'z');
      final listB = CRDTFugueMovableListHandler<String>(b, 'l');
      b.importChanges(a.exportChanges());
      expect(listB.value, equals(['x', 'y', 'z']));

      // The same element, two destinations.
      _levelClocks(a, b);
      listA.move(0, 2);
      listB.move(0, 1);

      _expectTie(listA.operations().last, listB.operations().last);

      a.importChanges(b.exportChanges());
      b.importChanges(a.exportChanges());

      expect(listA.value, equals(listB.value));
    });
  });
}
