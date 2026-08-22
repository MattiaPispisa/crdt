import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/algorithm/fugue/value_node.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

/// A stamp written by [peer] at logical time [l].
OperationId _stamp(PeerId peer, int l) =>
    OperationId(peer, HybridLogicalClock(l: l, c: 0));

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

    test('insert with no usable origin attaches under the root', () {
      final tree = FugueTree<dynamic>.empty();
      final peerId = PeerId.parse('ee121333-c65b-4afc-b226-4ef116df3432');
      final leftOrigin = FugueElementID.nullID();
      // Never inserted, so neither origin can be resolved.
      final rightOrigin = FugueElementID(peerId, 0);

      tree.insert(
        newID: FugueElementID(peerId, 1),
        value: 'test',
        leftOrigin: leftOrigin,
        rightOrigin: rightOrigin,
      );

      expect(tree.values(), equals(['test']));
    });

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

    test('insert throws on a tombstoned duplicate, leaving the tree intact',
        () {
      final tree = FugueTree<String>.empty();
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');
      final nullID = FugueElementID.nullID();

      // A → B with X sitting between them, so A carries a subtree.
      final a = FugueElementID(peerId, 1);
      final b = FugueElementID(peerId, 2);
      final x = FugueElementID(peerId, 3);
      tree
        ..insert(newID: a, value: 'A', leftOrigin: nullID, rightOrigin: nullID)
        ..insert(newID: b, value: 'B', leftOrigin: a, rightOrigin: nullID)
        ..insert(newID: x, value: 'X', leftOrigin: a, rightOrigin: b)
        ..delete(a, stamp: _stamp(peerId, 1));

      expect(tree.values(), equals(['X', 'B']));

      // Re-linking the tombstone would drop A's subtree and list A twice
      // among the root's children.
      expect(
        () => tree.insert(
          newID: a,
          value: 'A',
          leftOrigin: nullID,
          rightOrigin: b,
        ),
        throwsA(isA<DuplicateNodeException>()),
      );
      expect(tree.values(), equals(['X', 'B']));
    });

    test('findNodeAtPosition returns null for invalid position', () {
      final tree = FugueTree<dynamic>.empty();
      final result = tree.findNodeAtPosition(10);
      expect(result.isNull, isTrue);
    });

    test('findNextNode returns null for the root of an empty tree', () {
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

      tree.delete(nodeId, stamp: _stamp(peerId, 1));
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
      tree.delete(FugueElementID(peerId, 2), stamp: _stamp(peerId, 1));
      expect(tree.values(), equals(['a', 'c']));
    });

    test('findNextNode returns the in-order successor', () {
      final tree = FugueTree<String>.empty();
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');
      final nullID = FugueElementID.nullID();

      // A right-children chain X → Y → Z ...
      final x = FugueElementID(peerId, 1);
      final y = FugueElementID(peerId, 2);
      final z = FugueElementID(peerId, 3);
      tree
        ..insert(newID: x, value: 'X', leftOrigin: nullID, rightOrigin: nullID)
        ..insert(newID: y, value: 'Y', leftOrigin: x, rightOrigin: nullID)
        ..insert(newID: z, value: 'Z', leftOrigin: y, rightOrigin: nullID);

      // ... with two left children hanging under Z.
      final a = FugueElementID(peerId, 4);
      final b = FugueElementID(peerId, 5);
      tree
        ..insert(newID: a, value: 'A', leftOrigin: y, rightOrigin: z)
        ..insert(newID: b, value: 'B', leftOrigin: y, rightOrigin: z);

      expect(tree.values(), equals(['X', 'Y', 'A', 'B', 'Z']));

      // The successor of a node with right children opens that subtree by its
      // left spine, not by the right child itself.
      expect(tree.findNextNode(y), a);
      // A sibling on the same side comes next ...
      expect(tree.findNextNode(a), b);
      // ... and the last left child is followed by its own parent.
      expect(tree.findNextNode(b), z);
      expect(tree.findNextNode(x), y);
      expect(tree.findNextNode(z).isNull, isTrue);
    });

    test(
        'positions follow the visible order after a concurrent same-anchor '
        'insert', () {
      final base = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');
      // p2 sorts before p1, so the second batch lands ahead of the first.
      final p1 = PeerId.parse('ee121333-c65b-4afc-b226-4ef116df3432');
      final p2 = PeerId.parse('7c9e2b1a-3f4d-4a8b-9c0e-1d2f3a4b5c6d');
      final nullID = FugueElementID.nullID();

      final a = FugueElementID(base, 1);
      final b = FugueElementID(base, 2);
      final tree = FugueTree<String>.empty()
        ..insert(newID: a, value: 'A', leftOrigin: nullID, rightOrigin: nullID)
        ..insert(newID: b, value: 'B', leftOrigin: a, rightOrigin: nullID)
        ..iterableInsertChain(
          leftOrigin: a,
          rightOrigin: b,
          nodes: [
            FugueValueNode(id: FugueElementID(p1, 1), value: 'x1'),
            FugueValueNode(id: FugueElementID(p1, 2), value: 'x2'),
          ],
        )
        ..iterableInsertChain(
          leftOrigin: a,
          rightOrigin: b,
          nodes: [
            FugueValueNode(id: FugueElementID(p2, 1), value: 'y1'),
            FugueValueNode(id: FugueElementID(p2, 2), value: 'y2'),
          ],
        );

      expect(tree.values(), equals(['A', 'y1', 'y2', 'x1', 'x2', 'B']));

      // The second batch opens the region of `b`, so every position after it
      // has to shift: reading positions must not still report the old layout.
      final nodes = tree.nodes();
      for (var i = 0; i < nodes.length; i++) {
        expect(tree.findNodeAtPosition(i), nodes[i].id, reason: 'position $i');
      }
    });

    test('the head of the sequence can sit in the left subtree of the root',
        () {
      final tree = FugueTree<String>.empty();
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');
      final nullID = FugueElementID.nullID();

      final b = FugueElementID(peerId, 1);
      tree.insert(
        newID: b,
        value: 'B',
        leftOrigin: nullID,
        rightOrigin: nullID,
      );

      // An insert whose leftOrigin is unknown to this tree — the shape a
      // pruned origin produces — hangs off the left of the root.
      final l = FugueElementID(peerId, 2);
      tree.insert(
        newID: l,
        value: 'L',
        leftOrigin: FugueElementID(peerId, 99),
        rightOrigin: nullID,
      );

      expect(tree.values(), equals(['L', 'B']));
      // The root sits before everything, so its successor is the head of the
      // sequence and not the head of its right subtree.
      expect(tree.findNextNode(nullID), l);

      // An insert at index 0 therefore lands in front of L.
      tree.iterableInsert(0, [
        FugueValueNode(id: FugueElementID(peerId, 3), value: 'Z'),
      ]);
      expect(tree.values(), equals(['Z', 'L', 'B']));
    });

    test('insert attaches to rightOrigin when it descends from leftOrigin', () {
      final tree = FugueTree<String>.empty();
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');
      final nullID = FugueElementID.nullID();

      final x = FugueElementID(peerId, 1);
      final y = FugueElementID(peerId, 2);
      final z = FugueElementID(peerId, 3);
      final a = FugueElementID(peerId, 4);
      tree
        ..insert(newID: x, value: 'X', leftOrigin: nullID, rightOrigin: nullID)
        ..insert(newID: y, value: 'Y', leftOrigin: x, rightOrigin: nullID)
        ..insert(newID: z, value: 'Z', leftOrigin: y, rightOrigin: nullID)
        ..insert(newID: a, value: 'A', leftOrigin: y, rightOrigin: z)
        // A is a left child of Z, so it is a grandchild of Y rather than one
        // of its children: the placement rule still has to see the descendance.
        ..insert(
          newID: FugueElementID(peerId, 5),
          value: 'B',
          leftOrigin: y,
          rightOrigin: a,
        );

      expect(tree.values(), equals(['X', 'Y', 'B', 'A', 'Z']));
    });

    group('update', () {
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');
      // Pinned in ascending order: the peer settles two updates that share a
      // clock, so the winner has to be known in advance.
      final lowPeer = PeerId.parse('00000000-0000-4000-8000-00000000000a');
      final highPeer = PeerId.parse('00000000-0000-4000-8000-00000000000b');
      final nullID = FugueElementID.nullID();

      final a = FugueElementID(peerId, 1);
      final b = FugueElementID(peerId, 2);
      final c = FugueElementID(peerId, 3);

      FugueTree<String> abc() {
        return FugueTree<String>.empty()
          ..insert(
            newID: a,
            value: 'A',
            leftOrigin: nullID,
            rightOrigin: nullID,
          )
          ..insert(newID: b, value: 'B', leftOrigin: a, rightOrigin: nullID)
          ..insert(newID: c, value: 'C', leftOrigin: b, rightOrigin: nullID);
      }

      test('overwrites in place, keeping identity and position', () {
        final tree = abc();

        expect(
          tree.update(nodeID: b, value: 'B2', stamp: _stamp(peerId, 10)),
          isTrue,
        );

        expect(tree.values(), equals(['A', 'B2', 'C']));
        expect(tree.nodes().map((n) => n.id).toList(), equals([a, b, c]));
      });

      test('the higher stamp wins, whatever order the two arrive in', () {
        final early = _stamp(peerId, 10);
        final late = _stamp(peerId, 20);

        final forward = abc()
          ..update(nodeID: b, value: 'early', stamp: early)
          ..update(nodeID: b, value: 'late', stamp: late);
        final backward = abc()
          ..update(nodeID: b, value: 'late', stamp: late)
          ..update(nodeID: b, value: 'early', stamp: early);

        expect(forward.values(), equals(backward.values()));
        expect(forward.values(), equals(['A', 'late', 'C']));
      });

      test('the peer settles two updates that share a clock', () {
        final low = _stamp(lowPeer, 10);
        final high = _stamp(highPeer, 10);
        expect(low.hlc.compareTo(high.hlc), equals(0));

        final forward = abc()
          ..update(nodeID: b, value: 'from low', stamp: low)
          ..update(nodeID: b, value: 'from high', stamp: high);
        final backward = abc()
          ..update(nodeID: b, value: 'from high', stamp: high)
          ..update(nodeID: b, value: 'from low', stamp: low);

        expect(forward.values(), equals(backward.values()));
        expect(forward.values(), equals(['A', 'from high', 'C']));
      });

      test('re-applying the same update changes nothing', () {
        final tree = abc();
        final stamp = _stamp(peerId, 10);

        expect(tree.update(nodeID: b, value: 'B2', stamp: stamp), isTrue);
        expect(tree.update(nodeID: b, value: 'B2', stamp: stamp), isFalse);
        expect(tree.values(), equals(['A', 'B2', 'C']));
      });

      test('an unknown node is refused and leaves the tree alone', () {
        final tree = abc();
        final stranger = FugueElementID(peerId, 99);

        expect(
          tree.update(nodeID: stranger, value: 'X', stamp: _stamp(peerId, 10)),
          isFalse,
        );
        expect(tree.values(), equals(['A', 'B', 'C']));
        expect(tree.findNextNode(a), equals(b));
      });

      // A deletion is monotone: whichever way the two are ordered, the element
      // stays gone.
      test('a tombstone is never brought back, in either order', () {
        final deleteFirst = abc()..delete(b, stamp: _stamp(peerId, 1));
        expect(
          deleteFirst.update(nodeID: b, value: 'B2', stamp: _stamp(peerId, 10)),
          isFalse,
        );

        final updateFirst = abc()
          ..update(nodeID: b, value: 'B2', stamp: _stamp(peerId, 10))
          ..delete(b, stamp: _stamp(peerId, 1));

        expect(deleteFirst.values(), equals(updateFirst.values()));
        expect(deleteFirst.values(), equals(['A', 'C']));
      });

      // The tombstone holds on to everything the element had, so it can be
      // put back the way it was — and it still refuses a later update, which
      // now rests on the flag rather than on the value being gone.
      test(
          'deleting keeps the value and the stamp, and still refuses an update',
          () {
        final tree = abc()
          ..update(nodeID: b, value: 'B2', stamp: _stamp(peerId, 10))
          ..delete(b, stamp: _stamp(peerId, 1));

        expect(
          tree.update(nodeID: b, value: 'B3', stamp: _stamp(peerId, 30)),
          isFalse,
        );
        expect(tree.values(), equals(['A', 'C']));
        expect(tree.stamps[b], equals(_stamp(peerId, 10)));
        expect(tree.livenessStamps[b], equals(_stamp(peerId, 1)));
      });

      // Nothing reads the liveness stamp yet, but it has to be the same on
      // every peer the day something does. Arrival order is not: the Fugue
      // handlers fold changes as they turn up, and replay orders them by
      // clock and peer.
      test('two deletes of the same node keep the greater stamp, either way',
          () {
        final low = _stamp(peerId, 5);
        final high = _stamp(peerId, 9);

        final lowFirst = abc()
          ..delete(b, stamp: low)
          ..delete(b, stamp: high);
        final highFirst = abc()
          ..delete(b, stamp: high)
          ..delete(b, stamp: low);

        expect(lowFirst.livenessStamps[b], equals(high));
        expect(highFirst.livenessStamps[b], equals(high));
        expect(lowFirst.values(), equals(highFirst.values()));
      });

      // Two peers can mint the same clock, and then the peer is all that is
      // left to settle it.
      test('the peer settles two deletes carrying the same clock', () {
        final lowPeer = PeerId.parse('00000000-0000-4000-8000-00000000000a');
        final highPeer = PeerId.parse('00000000-0000-4000-8000-00000000000b');
        final fromLow = _stamp(lowPeer, 5);
        final fromHigh = _stamp(highPeer, 5);

        final lowFirst = abc()
          ..delete(b, stamp: fromLow)
          ..delete(b, stamp: fromHigh);
        final highFirst = abc()
          ..delete(b, stamp: fromHigh)
          ..delete(b, stamp: fromLow);

        expect(lowFirst.livenessStamps[b], equals(fromHigh));
        expect(highFirst.livenessStamps[b], equals(fromHigh));
      });

      // Nothing about liveness or traversal order changes, so the positional
      // index must not even notice.
      test('leaves every positional query untouched', () {
        final tree = abc();
        final ids = [a, b, c];

        List<Object?> queries() => [
              for (var i = 0; i < 3; i++) tree.findNodeAtPosition(i),
              for (final id in ids) tree.findNextNode(id),
              for (final id in ids) tree.liveIndexAfter(id),
            ];

        final before = queries();
        tree.update(nodeID: b, value: 'B2', stamp: _stamp(peerId, 10));

        expect(queries(), equals(before));
      });

      test('a json round-trip keeps the stamps, so a stale update still loses',
          () {
        final tree = abc()
          ..update(nodeID: b, value: 'B2', stamp: _stamp(peerId, 20));

        final restored = FugueTree<String>.fromJson(tree.toJson());
        expect(restored.values(), equals(['A', 'B2', 'C']));

        expect(
          restored.update(nodeID: b, value: 'stale', stamp: _stamp(peerId, 10)),
          isFalse,
        );
        expect(restored.values(), equals(['A', 'B2', 'C']));
      });
    });

    test('the sequence does not depend on the order operations are applied in',
        () {
      final base = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');
      final p1 = PeerId.parse('ee121333-c65b-4afc-b226-4ef116df3432');
      final p2 = PeerId.parse('7c9e2b1a-3f4d-4a8b-9c0e-1d2f3a4b5c6d');
      final nullID = FugueElementID.nullID();

      final a = FugueElementID(base, 1);
      final b = FugueElementID(base, 2);
      final c = FugueElementID(base, 3);

      // Four groups of operations, all generated against the same base state
      // (so they are mutually concurrent) and therefore applicable in any
      // order. Within a group the order is causal and preserved.
      final groups = <void Function(FugueTree<String>)>[
        (tree) => tree.iterableInsertChain(
              leftOrigin: a,
              rightOrigin: b,
              nodes: [
                FugueValueNode(id: FugueElementID(p1, 1), value: 'x1'),
                FugueValueNode(id: FugueElementID(p1, 2), value: 'x2'),
              ],
            ),
        (tree) => tree.iterableInsertChain(
              leftOrigin: a,
              rightOrigin: b,
              nodes: [
                FugueValueNode(id: FugueElementID(p2, 1), value: 'y1'),
                FugueValueNode(id: FugueElementID(p2, 2), value: 'y2'),
              ],
            ),
        (tree) => tree.insert(
              newID: FugueElementID(p2, 3),
              value: 'z',
              leftOrigin: b,
              rightOrigin: c,
            ),
        (tree) => tree.update(
              nodeID: b,
              value: 'B2',
              stamp: _stamp(p1, 10),
            ),
      ];

      List<String> applyInOrder(List<int> order) {
        final tree = FugueTree<String>.empty()
          ..insert(
            newID: a,
            value: 'A',
            leftOrigin: nullID,
            rightOrigin: nullID,
          )
          ..insert(newID: b, value: 'B', leftOrigin: a, rightOrigin: nullID)
          ..insert(newID: c, value: 'C', leftOrigin: b, rightOrigin: nullID);
        for (final index in order) {
          groups[index](tree);
        }
        return tree.values();
      }

      final permutations = <List<int>>[];
      void permute(List<int> chosen, List<int> remaining) {
        if (remaining.isEmpty) {
          permutations.add(chosen);
          return;
        }
        for (var i = 0; i < remaining.length; i++) {
          permute(
            [...chosen, remaining[i]],
            [...remaining]..removeAt(i),
          );
        }
      }

      permute([], [0, 1, 2, 3]);
      expect(permutations, hasLength(24));

      final expected = applyInOrder(permutations.first);
      for (final order in permutations.skip(1)) {
        expect(applyInOrder(order), equals(expected), reason: 'order $order');
      }
    });

    test('a chained batch insert matches element-by-element inserts', () {
      final peerId = PeerId.parse('4e91a152-582f-4f46-8944-c2c2e8b217ff');
      final nullID = FugueElementID.nullID();
      final p = FugueElementID(peerId, 5);
      final q = FugueElementID(peerId, 6);

      // X Y A Z, where A is a left child of Z: inserting at index 2 lands on
      // the branch where the new node hangs off rightOrigin.
      FugueTree<String> base() {
        final x = FugueElementID(peerId, 1);
        final y = FugueElementID(peerId, 2);
        final z = FugueElementID(peerId, 3);
        return FugueTree<String>.empty()
          ..insert(
            newID: x,
            value: 'X',
            leftOrigin: nullID,
            rightOrigin: nullID,
          )
          ..insert(newID: y, value: 'Y', leftOrigin: x, rightOrigin: nullID)
          ..insert(newID: z, value: 'Z', leftOrigin: y, rightOrigin: nullID)
          ..insert(
            newID: FugueElementID(peerId, 4),
            value: 'A',
            leftOrigin: y,
            rightOrigin: z,
          );
      }

      final batched = base()
        ..iterableInsert(2, [
          FugueValueNode(id: p, value: 'p'),
          FugueValueNode(id: q, value: 'q'),
        ]);
      final oneByOne = base()
        ..iterableInsert(2, [FugueValueNode(id: p, value: 'p')])
        ..iterableInsert(3, [FugueValueNode(id: q, value: 'q')]);

      expect(batched.values(), equals(['X', 'Y', 'p', 'q', 'A', 'Z']));
      expect(
        batched.nodes().map((node) => node.id).toList(),
        equals(oneByOne.nodes().map((node) => node.id).toList()),
      );
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

      // Everything the tree exposes about order — `values`, `nodes`,
      // `findNodeAtPosition`, `findNextNode` — is now served by the positional
      // index, so the oracle has to come from somewhere else: an in-order walk
      // of the serialized tree, which is the structure the index mirrors.
      List<String> structuralSequence(FugueTree<String> t) {
        final nodesJson = t.toJson()['nodes']! as Map<String, dynamic>;
        final sequence = <String>[];
        void visit(String id) {
          final triple = nodesJson[id]! as Map<String, dynamic>;
          for (final child in triple['leftChildren']! as List<dynamic>) {
            visit(
              FugueElementID.fromJson(child as Map<String, dynamic>).toString(),
            );
          }
          if (id != 'null') {
            sequence.add(id);
          }
          for (final child in triple['rightChildren']! as List<dynamic>) {
            visit(
              FugueElementID.fromJson(child as Map<String, dynamic>).toString(),
            );
          }
        }

        visit('null');
        return sequence;
      }

      void checkAgainstOracle(FugueTree<String> t, int step) {
        final nodesJson = t.toJson()['nodes']! as Map<String, dynamic>;
        final live = <String>[];
        for (final id in structuralSequence(t)) {
          final triple = nodesJson[id]! as Map<String, dynamic>;
          final node = triple['node']! as Map<String, dynamic>;
          // A tombstone keeps its value, so the flag is what says it is gone.
          if (node['deleted'] != true) {
            live.add(id);
          }
        }

        expect(
          t.nodes().map((n) => n.id.toString()).toList(),
          equals(live),
          reason: 'live sequence at step $step',
        );
        expect(
          t.liveLength,
          live.length,
          reason: 'liveLength at step $step',
        );
        for (var i = 0; i < live.length; i++) {
          expect(
            t.findNodeAtPosition(i).toString(),
            live[i],
            reason: 'position $i at step $step',
          );
        }
        expect(t.findNodeAtPosition(-1).isNull, isTrue);
        expect(t.findNodeAtPosition(live.length).isNull, isTrue);
      }

      // `findNextNode` must also walk tombstones, which the live oracle above
      // cannot see, so it is checked against the full structural sequence.
      void checkSuccessorsAgainstOracle(FugueTree<String> t, int step) {
        final sequence = structuralSequence(t);
        for (var i = 0; i < sequence.length; i++) {
          expect(
            t.findNextNode(FugueElementID.parse(sequence[i])).toString(),
            i + 1 < sequence.length ? sequence[i + 1] : 'null',
            reason: 'successor of ${sequence[i]} at step $step',
          );
        }
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
          tree.delete(
            live[rng.nextInt(live.length)].id,
            stamp: _stamp(peerId, step),
          );
        } else {
          // A strictly growing clock, so every update wins and the value the
          // oracle sees is the one just written.
          tree.update(
            nodeID: live[rng.nextInt(live.length)].id,
            value: 'u$step',
            stamp: _stamp(peerId, step + 1),
          );
        }

        checkAgainstOracle(tree, step);
        // Quadratic in the tree size, so sampled rather than run every step.
        if (step % 100 == 0) {
          checkSuccessorsAgainstOracle(tree, step);
        }
      }
      checkSuccessorsAgainstOracle(tree, 1500);

      // A json round-trip rebuilds the index and reproduces the same sequence.
      final restored = FugueTree<String>.fromJson(tree.toJson());
      final oracle = tree.nodes().map((n) => n.id).toList();
      expect(restored.nodes().map((n) => n.id).toList(), oracle);
      checkAgainstOracle(restored, -1);
    });
  });
}
