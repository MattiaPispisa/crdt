import 'package:test/test.dart';
import 'package:crdt_lf/src/dag/graph.dart';
import 'package:crdt_lf/src/operation/id.dart';
import 'package:crdt_lf/src/peer_id.dart';
import 'package:hlc_dart/hlc_dart.dart';

void main() {
  group('DAG', () {
    late DAG dag;
    late PeerId author;
    late OperationId id1;
    late OperationId id2;
    late OperationId id3;
    late OperationId id4;

    setUp(() {
      dag = DAG.empty();
      author = PeerId.generate();

      final hlc1 = HybridLogicalClock(l: 1, c: 1);
      final hlc2 = HybridLogicalClock(l: 1, c: 2);
      final hlc3 = HybridLogicalClock(l: 1, c: 3);
      final hlc4 = HybridLogicalClock(l: 1, c: 4);

      id1 = OperationId(author, hlc1);
      id2 = OperationId(author, hlc2);
      id3 = OperationId(author, hlc3);
      id4 = OperationId(author, hlc4);
    });

    test('empty constructor creates empty DAG', () {
      expect(dag.nodeCount, equals(0));
      expect(dag.frontiers, isEmpty);
    });

    test('addNode adds a root node', () {
      dag.addNode(id1, {});
      expect(dag.nodeCount, equals(1));
      expect(dag.containsNode(id1), isTrue);
      expect(dag.frontiers, equals({id1}));
    });

    test('addNode adds a node with dependencies', () {
      dag.addNode(id1, {});
      dag.addNode(id2, {id1});
      dag.addNode(id3, {id2});

      expect(dag.nodeCount, equals(3));
      expect(dag.containsNode(id1), isTrue);
      expect(dag.containsNode(id2), isTrue);
      expect(dag.containsNode(id3), isTrue);
      expect(dag.frontiers, equals({id3}));
    });

    test('addNode throws when adding duplicate node', () {
      dag.addNode(id1, {});
      expect(
        () => dag.addNode(id1, {}),
        throwsA(isA<StateError>()),
      );
    });

    test('addNode throws when dependency does not exist', () {
      expect(
        () => dag.addNode(id1, {id2}),
        throwsA(isA<StateError>()),
      );
    });

    test('getNode returns correct node', () {
      dag.addNode(id1, {});
      dag.addNode(id2, {id1});

      final node1 = dag.getNode(id1);
      final node2 = dag.getNode(id2);

      expect(node1, isNotNull);
      expect(node2, isNotNull);
      expect(node1!.id, equals(id1));
      expect(node2!.id, equals(id2));
      expect(node2.hasParent(id1), isTrue);
      expect(node1.hasChild(id2), isTrue);
    });

    test('getNode returns null for non-existent node', () {
      expect(dag.getNode(id1), isNull);
    });

    test('isReady checks if dependencies exist', () {
      dag.addNode(id1, {});
      dag.addNode(id2, {id1});

      expect(dag.isReady({}), isTrue);
      expect(dag.isReady({id1}), isTrue);
      expect(dag.isReady({id2}), isTrue);
      expect(dag.isReady({id3}), isFalse);
    });

    test('getAncestors returns all ancestors', () {
      dag.addNode(id1, {});
      dag.addNode(id2, {id1});
      dag.addNode(id3, {id2});
      dag.addNode(id4, {id2});

      final ancestors1 = dag.getAncestors(id1);
      final ancestors2 = dag.getAncestors(id2);
      final ancestors3 = dag.getAncestors(id3);
      final ancestors4 = dag.getAncestors(id4);

      expect(ancestors1, equals({id1}));
      expect(ancestors2, equals({id1, id2}));
      expect(ancestors3, equals({id1, id2, id3}));
      expect(ancestors4, equals({id1, id2, id4}));
    });

    test('getAncestors throws for non-existent node', () {
      expect(
        () => dag.getAncestors(id1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getLCA finds lowest common ancestors', () {
      dag.addNode(id1, {});
      dag.addNode(id2, {id1});
      dag.addNode(id3, {id2});
      dag.addNode(id4, {id2});

      final lca1 = dag.getLCA({id3}, {id4});
      final lca2 = dag.getLCA({id1}, {id3});
      final lca3 = dag.getLCA({id3}, {id1});
      final lca4 = dag.getLCA({}, {id1});
      final lca5 = dag.getLCA({id1}, {});

      expect(lca1, equals({id2}));
      expect(lca2, equals({id1}));
      expect(lca3, equals({id1}));
      expect(lca4, isEmpty);
      expect(lca5, isEmpty);
    });

    test('merge combines two DAGs', () {
      // Create first DAG
      dag.addNode(id1, {});
      dag.addNode(id2, {id1});

      // Create second DAG
      final otherDag = DAG.empty();
      otherDag.addNode(id3, {});
      otherDag.addNode(id4, {id3});

      // Merge DAGs
      dag.merge(otherDag);

      expect(dag.nodeCount, equals(4));
      expect(dag.containsNode(id1), isTrue);
      expect(dag.containsNode(id2), isTrue);
      expect(dag.containsNode(id3), isTrue);
      expect(dag.containsNode(id4), isTrue);
      expect(dag.frontiers, equals({id4}));
    });

    test('toString returns correct string representation', () {
      dag.addNode(id1, {});
      dag.addNode(id2, {id1});

      final expected =
          'DAG(nodes: [\nDAGNode(id: $id1, parents: [], children: [$id2])\nDAGNode(id: $id2, parents: [$id1], children: [])\n], frontiers: ${
        id2
      })';
      expect(dag.toString(), equals(expected));
    });
  });
}
