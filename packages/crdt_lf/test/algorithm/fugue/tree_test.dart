import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('FugueTree', () {
    test('empty creates a tree with root node', () {
      final tree = FugueTree<dynamic>.empty();
      expect(tree.values(), isEmpty);
    });

    test('fromJson creates tree from JSON', () {
      final json = {
        'nodes': {
          'null': {
            'node': {
              'id': {'replicaID': '', 'counter': null},
              'value': null,
              'parentID': {'replicaID': '', 'counter': null},
              'side': 'left',
            },
            'leftChildren': <dynamic>[],
            'rightChildren': <dynamic>[],
          },
        },
      };

      final tree = FugueTree<dynamic>.fromJson(json);
      expect(tree.values(), isEmpty);
    });

    test('toJson serializes tree to JSON', () {
      final tree = FugueTree<dynamic>.empty();
      final json = tree.toJson();
      expect(json, isA<Map<String, dynamic>>());
      expect(json['nodes'], isA<Map<String, dynamic>>());
    });

    test('toString returns tree representation', () {
      final tree = FugueTree<dynamic>.empty();
      final str = tree.toString();
      expect(str, contains('Tree:'));
    });

    test('insert with rightOrigin creates right child', () {
      final tree = FugueTree<dynamic>.empty();
      final peerId = PeerId.parse('ee121333-c65b-4afc-b226-4ef116df3432');
      final leftOrigin = FugueElementID.nullID();
      final rightOrigin = FugueElementID(peerId, 0);

      tree.insert(
        newID: FugueElementID(peerId, 1),
        value: 'test',
        leftOrigin: leftOrigin,
        rightOrigin: rightOrigin,
      );

      expect(tree.values(), equals(['test']));
    });

    test(
      'update ',
      () {
        final tree = FugueTree<dynamic>.empty();
        final peerId = PeerId.parse('ee121333-c65b-4afc-b226-4ef116df3432');
        final leftOrigin = FugueElementID.nullID();
        final rightOrigin = FugueElementID(peerId, 0);

        tree
          ..insert(
            newID: FugueElementID(peerId, 1),
            value: 'test',
            leftOrigin: leftOrigin,
            rightOrigin: rightOrigin,
          )
          ..update(
            newID: FugueElementID(peerId, 2),
            newValue: 'Test!',
            nodeID: FugueElementID(peerId, 1),
          );

        expect(tree.values(), equals(['Test!']));
      },
    );

    test('insert with leftOrigin creates right child', () {
      final tree = FugueTree<dynamic>.empty();
      final peerId = PeerId.parse('ee121333-c65b-4afc-b226-4ef116df3432');

      // First insert a node
      final firstNode = FugueElementID(peerId, 1);
      tree
        ..insert(
          newID: firstNode,
          value: 'first',
          leftOrigin: FugueElementID.nullID(),
          rightOrigin: FugueElementID.nullID(),
        )

        // Then insert a node with leftOrigin
        ..insert(
          newID: FugueElementID(peerId, 2),
          value: 'second',
          leftOrigin: firstNode,
          rightOrigin: FugueElementID.nullID(),
        );

      expect(tree.values(), equals(['first', 'second']));
    });

    test('should be attached under root', () {
      final tree = FugueTree<dynamic>.empty();
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');

      expect(
        () => tree.insert(
          newID: FugueElementID(peerId, 1),
          value: 'test',
          leftOrigin: FugueElementID.nullID(), // Invalid parent
          rightOrigin: FugueElementID.nullID(),
        ),
        returnsNormally,
      );
    });

    test('insert throws on duplicate node', () {
      final tree = FugueTree<dynamic>.empty();
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');
      final nodeId = FugueElementID(peerId, 1);

      // Insert first time
      tree.insert(
        newID: nodeId,
        value: 'test',
        leftOrigin: FugueElementID.nullID(),
        rightOrigin: FugueElementID.nullID(),
      );

      // Try to insert again
      expect(
        () => tree.insert(
          newID: nodeId,
          value: 'test2',
          leftOrigin: FugueElementID.nullID(),
          rightOrigin: FugueElementID.nullID(),
        ),
        throwsA(isA<DuplicateNodeException>()),
      );
    });

    test('findNodeAtPosition returns null for invalid position', () {
      final tree = FugueTree<dynamic>.empty();
      final result = tree.findNodeAtPosition(10);
      expect(result.isNull, isTrue);
    });

    test('findNextNode returns null for last node', () {
      final tree = FugueTree<dynamic>.empty();
      final result = tree.findNextNode(FugueElementID.nullID());
      expect(result.isNull, isTrue);
    });

    test('delete marks node as deleted', () {
      final tree = FugueTree<dynamic>.empty();
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');
      final nodeId = FugueElementID(peerId, 1);

      tree.insert(
        newID: nodeId,
        value: 'test',
        leftOrigin: FugueElementID.nullID(),
        rightOrigin: FugueElementID.nullID(),
      );

      expect(tree.values(), equals(['test']));

      tree.delete(nodeId);
      expect(tree.values(), isEmpty);
    });

    test(
        'insert with unknown leftOrigin and null rightOrigin '
        'falls back to root left side', () {
      final tree = FugueTree<dynamic>.empty();
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');
      // leftOrigin is a node id that has never been inserted, and
      // rightOrigin is null. This should still produce a usable node.
      final unknownLeft = FugueElementID(peerId, 42);

      tree.insert(
        newID: FugueElementID(peerId, 1),
        value: 'fallback',
        leftOrigin: unknownLeft,
        rightOrigin: FugueElementID.nullID(),
      );

      expect(tree.values(), equals(['fallback']));
    });

    test('findNextNode returns null when nodeID is not in tree', () {
      final tree = FugueTree<dynamic>.empty();
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');
      // Use an ID that has not been inserted.
      final unknown = FugueElementID(peerId, 999);
      final result = tree.findNextNode(unknown);
      expect(result.isNull, isTrue);
    });

    test('toString renders a tree with left and right children', () {
      final tree = FugueTree<dynamic>.empty();
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');
      final root = FugueElementID(peerId, 1);
      // root node as a right child of the implicit tree root
      tree
        ..insert(
          newID: root,
          value: 'root',
          leftOrigin: FugueElementID.nullID(),
          rightOrigin: FugueElementID.nullID(),
        )
        // adds a right child of root
        ..insert(
          newID: FugueElementID(peerId, 2),
          value: 'right',
          leftOrigin: root,
          rightOrigin: FugueElementID.nullID(),
        )
        // adds a left child of root by setting rightOrigin=root
        ..insert(
          newID: FugueElementID(peerId, 3),
          value: 'left',
          leftOrigin: FugueElementID.nullID(),
          rightOrigin: root,
        );

      final str = tree.toString();
      expect(str, contains('Tree:'));
      expect(str, contains('Left children:'));
      expect(str, contains('Right children:'));
      // both children should appear in the rendering
      expect(str, contains('left'));
      expect(str, contains('right'));
    });

    test('values returns all non-deleted values in order', () {
      final tree = FugueTree<dynamic>.empty();
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');

      // Insert multiple values
      tree
        ..insert(
          newID: FugueElementID(peerId, 1),
          value: 'a',
          leftOrigin: FugueElementID.nullID(),
          rightOrigin: FugueElementID.nullID(),
        )
        ..insert(
          newID: FugueElementID(peerId, 2),
          value: 'b',
          leftOrigin: FugueElementID(peerId, 1),
          rightOrigin: FugueElementID.nullID(),
        )
        ..insert(
          newID: FugueElementID(peerId, 3),
          value: 'c',
          leftOrigin: FugueElementID(peerId, 2),
          rightOrigin: FugueElementID.nullID(),
        );

      expect(tree.values(), equals(['a', 'b', 'c']));

      // Delete middle value
      tree.delete(FugueElementID(peerId, 2));
      expect(tree.values(), equals(['a', 'c']));
    });

    test('findNodeAtPosition matches the live traversal order', () {
      final tree = FugueTree<dynamic>.empty();
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');

      var left = FugueElementID.nullID();
      for (var i = 1; i <= 5; i++) {
        final id = FugueElementID(peerId, i);
        tree.insert(
          newID: id,
          value: 'v$i',
          leftOrigin: left,
          rightOrigin: FugueElementID.nullID(),
        );
        left = id;
      }

      final nodes = tree.nodes();
      for (var i = 0; i < nodes.length; i++) {
        expect(tree.findNodeAtPosition(i), nodes[i].id);
      }
      expect(tree.findNodeAtPosition(-1).isNull, isTrue);
      expect(tree.findNodeAtPosition(nodes.length).isNull, isTrue);

      // Delete a middle node: positions shift down, no stale entry remains.
      tree.delete(FugueElementID(peerId, 3));
      final after = tree.nodes();
      for (var i = 0; i < after.length; i++) {
        expect(tree.findNodeAtPosition(i), after[i].id);
      }
    });

    test('findNextNode: last node has no successor (fast path)', () {
      final tree = FugueTree<dynamic>.empty();
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');

      final ids = [for (var i = 1; i <= 5; i++) FugueElementID(peerId, i)];
      var left = FugueElementID.nullID();
      for (final id in ids) {
        tree.insert(
          newID: id,
          value: '$id',
          leftOrigin: left,
          rightOrigin: FugueElementID.nullID(),
        );
        left = id;
      }

      // The in-order-last node has no successor.
      expect(tree.findNextNode(ids.last).isNull, isTrue);
      // A middle node still resolves to its right child (unchanged behavior).
      expect(tree.findNextNode(ids[2]), ids[3]);
    });

    test(
        'randomized differential: index agrees with the traversal oracle '
        'through inserts, deletes, updates and a json round-trip', () {
      final rng = Random(424242);
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');
      final tree = FugueTree<String>.empty();
      final created = <FugueElementID>[]; // every id ever inserted
      var counter = 0;

      FugueElementID nextId() => FugueElementID(peerId, counter++);

      void checkAgainstOracle(FugueTree<String> t, int step) {
        final oracle = t.nodes();
        for (var i = 0; i < oracle.length; i++) {
          expect(
            t.findNodeAtPosition(i),
            oracle[i].id,
            reason: 'position $i at step $step',
          );
        }
        expect(t.findNodeAtPosition(-1).isNull, isTrue);
        expect(t.findNodeAtPosition(oracle.length).isNull, isTrue);
      }

      for (var step = 0; step < 1500; step++) {
        final live = tree.nodes();
        final op = rng.nextInt(10);

        if (live.isEmpty || op < 6) {
          // Structural insert with random origins (covers right/left children,
          // sibling chains and root fallbacks).
          final id = nextId();
          final leftOrigin = created.isEmpty || rng.nextBool()
              ? FugueElementID.nullID()
              : created[rng.nextInt(created.length)];
          final rightOrigin = created.isNotEmpty && rng.nextInt(3) == 0
              ? created[rng.nextInt(created.length)]
              : FugueElementID.nullID();
          tree.insert(
            newID: id,
            value: 'v$counter',
            leftOrigin: leftOrigin,
            rightOrigin: rightOrigin,
          );
          created.add(id);
        } else if (op < 8) {
          tree.delete(live[rng.nextInt(live.length)].id);
        } else {
          final id = nextId();
          tree.update(
            nodeID: live[rng.nextInt(live.length)].id,
            newID: id,
            newValue: 'u$counter',
          );
          created.add(id);
        }

        checkAgainstOracle(tree, step);
      }

      // A json round-trip rebuilds the index and reproduces the same sequence.
      final restored = FugueTree<String>.fromJson(tree.toJson());
      final oracle = tree.nodes().map((n) => n.id).toList();
      expect(restored.nodes().map((n) => n.id).toList(), oracle);
      checkAgainstOracle(restored, -1);
    });
  });
}
