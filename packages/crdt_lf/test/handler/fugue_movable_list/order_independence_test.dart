import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

/// Pinned: a move and an update that share a clock are settled by the peer, so
/// a generated id would make the expected value depend on the run.
const _peerA = '00000000-0000-4000-8000-00000000000a';
const _peerB = '00000000-0000-4000-8000-00000000000b';
const _peerC = '00000000-0000-4000-8000-00000000000c';

/// A document seeded with a shared history, plus its list handler.
///
/// The handler is registered before the import so it sees the changes, which
/// is the "shared history" set-up the other cross-peer tests use.
class _Replica {
  _Replica(String peerId, [List<Change> history = const []])
      : doc = CRDTDocument(peerId: PeerId.parse(peerId)) {
    list = CRDTFugueMovableListHandler<String>(doc, 'list');
    if (history.isNotEmpty) {
      doc.importChanges(history);
    }
  }

  final CRDTDocument doc;
  late final CRDTFugueMovableListHandler<String> list;
}

/// The one change [edit] produces on a replica seeded with [history].
Change _edit(
  String peerId,
  List<Change> history,
  void Function(CRDTFugueMovableListHandler<String> list) edit,
) {
  final replica = _Replica(peerId, history);
  edit(replica.list);
  return replica.doc
      .exportChanges()
      .where((change) => !history.contains(change))
      .single;
}

/// Every ordering of [changes].
///
/// Enumerated rather than sampled: three changes is six orders, and a failure
/// has to be reproducible.
Iterable<List<Change>> _permutations(List<Change> changes) sync* {
  if (changes.length <= 1) {
    yield changes;
    return;
  }
  for (var i = 0; i < changes.length; i += 1) {
    final rest = [...changes]..removeAt(i);
    for (final tail in _permutations(rest)) {
      yield [changes[i], ...tail];
    }
  }
}

void main() {
  // `CRDTFugueMovableListHandler` declares `stateIsOrderIndependent`, which
  // lets the document fold a change that arrives **from the past** into the
  // cached state instead of replaying the history. That is sound only if the
  // state is the same whatever order causally ready changes arrive in.
  //
  // Every mutation is max-wins on `OperationStamp`: `insert` seeds the two
  // clocks and never overwrites them, `move` and `update` keep the greater
  // stamp, `delete` is monotone. The tree the positions live in sorts siblings
  // by element id, so it is a function of the operation set alone. These tests
  // are what keeps that true.
  group('CRDTFugueMovableListHandler order independence', () {
    late List<Change> history;

    setUp(() {
      final seed = _Replica(_peerA);
      seed.list.insertAll(0, ['a', 'b', 'c']);
      expect(seed.list.value, equals(['a', 'b', 'c']));
      history = seed.doc.exportChanges();
    });

    test('every arrival order of concurrent writes gives the same list', () {
      final concurrent = <Change>[
        _edit(_peerA, history, (list) => list.move(2, 0)),
        _edit(_peerB, history, (list) => list.update(1, 'B')),
        _edit(_peerC, history, (list) => list.move(0, 2)),
      ];

      final results = <String>{};
      for (final order in _permutations(concurrent)) {
        final replica = _Replica(_peerA, history);
        for (final change in order) {
          replica.doc.importChanges([change]);
        }
        results.add(replica.list.value.join(','));
      }

      expect(
        results,
        hasLength(1),
        reason: 'the six arrival orders produced: $results',
      );
    });

    test('a delete beats a concurrent move and update, in every order', () {
      final concurrent = <Change>[
        _edit(_peerA, history, (list) => list.delete(1)),
        _edit(_peerB, history, (list) => list.update(1, 'B')),
        _edit(_peerC, history, (list) => list.move(1, 0)),
      ];

      for (final order in _permutations(concurrent)) {
        final replica = _Replica(_peerA, history);
        for (final change in order) {
          replica.doc.importChanges([change]);
        }
        expect(replica.list.value, equals(['a', 'c']));
      }
    });

    // The path the flag actually opens: the reader already holds a cached
    // state and then a change **older** than the newest one it folded shows
    // up. With the flag it is folded in place; the answer has to match the
    // peer that replayed the whole sorted history.
    test('a change from the past folded into a warm cache agrees with a replay',
        () {
      final fromThePast = _edit(_peerB, history, (list) => list.update(1, 'B'));

      final later = _Replica(_peerC, history);
      later.list
        ..move(2, 0)
        ..update(1, 'C');
      final newer = later.doc
          .exportChanges()
          .where((change) => !history.contains(change))
          .toList();

      // Warm the cache with the newer changes, then hand it the older one.
      final incremental = _Replica(_peerA, history);
      incremental.doc.importChanges(newer);
      expect(incremental.list.value, isNotEmpty, reason: 'warms the cache');
      incremental.doc.importChanges([fromThePast]);

      // The same set, read only once, so the handler replays it sorted.
      final replayed = _Replica(_peerA, history);
      replayed.doc.importChanges([...newer, fromThePast]);

      expect(incremental.list.value, equals(replayed.list.value));
    });
  });
}
