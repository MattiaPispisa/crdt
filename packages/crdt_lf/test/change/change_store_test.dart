import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';

void main() {
  group('ChangeStore', () {
    late ChangeStore store;
    late Handler handler;
    late PeerId author;
    late Operation operation;
    late Change change1;
    late Change change2;
    late Change change3;
    late DAG dag;

    setUp(() {
      final doc = CRDTDocument();
      handler = TestHandler(doc);
      author = PeerId.generate();
      operation = TestOperation.fromHandler(handler);

      final hlc1 = HybridLogicalClock(l: 1, c: 1);
      final hlc2 = HybridLogicalClock(l: 1, c: 2);
      final hlc3 = HybridLogicalClock(l: 1, c: 3);

      final id1 = OperationId(author, hlc1);
      final id2 = OperationId(author, hlc2);
      final id3 = OperationId(author, hlc3);

      change1 = Change(
        id: id1,
        operation: operation,
        deps: {},
        hlc: hlc1,
        author: author,
      );

      change2 = Change(
        id: id2,
        operation: operation,
        deps: {id1},
        hlc: hlc2,
        author: author,
      );

      change3 = Change(
        id: id3,
        operation: operation,
        deps: {id2},
        hlc: hlc3,
        author: author,
      );

      store = ChangeStore.empty();
      dag = DAG.empty();
    });

    test('empty constructor creates empty store', () {
      expect(store.changeCount, equals(0));
    });

    test('addChange adds a new change', () {
      final added = store.addChange(change1);
      expect(added, isTrue);
      expect(store.changeCount, equals(1));
      expect(store.containsChange(change1.id), isTrue);
      expect(store.getChange(change1.id), equals(change1));
    });

    test('addChange does not replace existing change', () {
      store.addChange(change1);
      final added = store.addChange(change1);
      expect(added, isFalse);
      expect(store.changeCount, equals(1));
    });

    test('getAllChanges returns all changes', () {
      store.addChange(change1);
      store.addChange(change2);
      store.addChange(change3);

      final changes = store.getAllChanges();
      expect(changes.length, equals(3));
      expect(changes, containsAll([change1, change2, change3]));
    });

    test('exportChanges with empty version returns all changes', () {
      store.addChange(change1);
      store.addChange(change2);
      store.addChange(change3);

      final changes = store.exportChanges({}, dag);
      expect(changes.length, equals(3));
      expect(changes, containsAll([change1, change2, change3]));
    });

    test('exportChanges with version returns non-ancestor changes', () {
      store.addChange(change1);
      store.addChange(change2);
      store.addChange(change3);

      // Add changes to DAG
      dag.addNode(change1.id, {});
      dag.addNode(change2.id, {change1.id});
      dag.addNode(change3.id, {change2.id});

      // Export changes from version containing change2
      final changes = store.exportChanges({change2.id}, dag);
      expect(changes.length, equals(1));
      expect(changes, contains(change3));
    });

    test('importChanges adds multiple changes', () {
      final changes = [change1, change2, change3];
      final added = store.importChanges(changes);
      expect(added, equals(3));
      expect(store.changeCount, equals(3));
      expect(store.getAllChanges(), containsAll(changes));
    });

    test('importChanges skips existing changes', () {
      store.addChange(change1);
      final changes = [change1, change2, change3];
      final added = store.importChanges(changes);
      expect(added, equals(2));
      expect(store.changeCount, equals(3));
      expect(store.getAllChanges(), containsAll(changes));
    });

    test('clear removes all changes', () {
      store.addChange(change1);
      store.addChange(change2);
      store.addChange(change3);

      store.clear();
      expect(store.changeCount, equals(0));
    });

    test('prune removes changes older than the given version vector', () {
      store.addChange(change1);
      store.addChange(change2);
      store.addChange(change3);

      store.prune(VersionVector({author: change2.hlc}));

      expect(store.changeCount, equals(1));
      expect(store.containsChange(change3.id), isTrue);
      expect(store.containsChange(change2.id), isFalse);
      expect(store.containsChange(change1.id), isFalse);
    });

    test('toString returns correct string representation', () {
      store.addChange(change1);
      store.addChange(change2);
      store.addChange(change3);

      expect(store.toString(), equals('ChangeStore(changes: 3)'));
    });
  });
}
