import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/change/change_log.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';

void main() {
  group('ChangeLog', () {
    late ChangeLog log;
    late Operation operation;
    late PeerId author;

    setUp(() {
      log = ChangeLog();
      author = PeerId.generate();
      operation = TestOperation.fromHandler(TestHandler(CRDTDocument()));
    });

    Change change(
      int counter, {
      Set<OperationId> deps = const {},
      PeerId? by,
      int physical = 1,
    }) {
      final peer = by ?? author;
      return Change(
        id: OperationId(peer, HybridLogicalClock(l: physical, c: counter)),
        operation: operation,
        deps: deps,
        author: peer,
      );
    }

    test('add takes a change once', () {
      final first = change(1);

      expect(log.add(first), isTrue);
      expect(log.add(first), isFalse);
      expect(log.changeCount, 1);
      expect(log.frontiers, {first.id});
      expect(log.versionVector[author], first.hlc);
    });

    test('add refuses a change whose dependency is missing', () {
      final first = change(1);

      expect(
        () => log.add(change(2, deps: {first.id})),
        throwsA(isA<CausallyNotReadyException>()),
      );
    });

    test('add takes a missing dependency the snapshot version covers', () {
      final first = change(1);
      final second = change(2, deps: {first.id});

      expect(
        log.add(second, snapshotVersion: VersionVector({author: first.hlc})),
        isTrue,
      );
      expect(log.frontiers, {second.id});
    });

    test('prune removes the changes the version has seen, from the graph too',
        () {
      final first = change(1);
      final second = change(2, deps: {first.id});
      log
        ..add(first)
        ..add(second)
        ..prune(VersionVector({author: first.hlc}));

      expect(log.exportChanges().map((c) => c.id), [second.id]);
      expect(
        () => log.add(change(3, deps: {first.id})),
        throwsA(isA<CausallyNotReadyException>()),
      );
    });

    test('sortTopologically puts dependencies first', () {
      final first = change(1);
      final second = change(2, deps: {first.id});
      final third = change(3, deps: {second.id});

      expect(
        ChangeLog.sortTopologically([third, second, first]),
        [first, second, third],
      );
    });

    test('sortTopologically throws on a cycle', () {
      final id1 = OperationId(author, HybridLogicalClock(l: 1, c: 1));
      final id2 = OperationId(author, HybridLogicalClock(l: 1, c: 2));
      final changes = [
        Change(id: id1, operation: operation, deps: {id2}, author: author),
        Change(id: id2, operation: operation, deps: {id1}, author: author),
      ];

      expect(
        () => ChangeLog.sortTopologically(changes),
        throwsA(isA<ChangesCycleException>()),
      );
    });

    test('exportChanges from a version returns what came after it', () {
      final first = change(1);
      final second = change(2, deps: {first.id});
      final third = change(3, deps: {second.id});
      log
        ..add(first)
        ..add(second)
        ..add(third);

      expect(
        log.exportChanges(from: {first.id}),
        unorderedEquals([second, third]),
      );
    });

    test('exportChangesNewerThan compares each peer on its own', () {
      final other = PeerId.generate();
      final a1 = change(1);
      final a2 = change(2, deps: {a1.id});
      final b1 = change(1, by: other, physical: 2);
      log
        ..add(a1)
        ..add(a2)
        ..add(b1);

      expect(
        log.exportChangesNewerThan(VersionVector({author: a1.hlc})),
        unorderedEquals([a2, b1]),
      );
    });
  });
}
