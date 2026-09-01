import 'package:crdt_lf/crdt_lf.dart';

/// One block of elements a delete takes out, and where it goes back.
///
/// See [fugueRestoreRuns] for how a block is cut.
class FugueRestoreRun<K extends Object, V> {
  /// Creates a run that goes back between [leftOrigin] and [rightOrigin].
  FugueRestoreRun({
    required this.leftOrigin,
    required this.rightOrigin,
    required this.items,
  });

  /// The tree node the block hangs off: the anchor of its **last** element.
  ///
  /// That node is a tombstone by the time the undo runs, and a tombstone is
  /// still a node of the tree, so the block lands back where it was taken
  /// from, whatever else has been written around it since.
  final FugueElementID leftOrigin;

  /// The node that followed [leftOrigin] when the run was cut.
  final FugueElementID rightOrigin;

  /// What goes back, in order: the identity that held each value before, and
  /// the value itself.
  final List<({K was, V value})> items;
}

/// Cuts the elements a delete takes out into the blocks that put them back.
///
/// [ids] are the identities the delete names, in the order it names them.
/// [probe] answers, for one of them: is it still there to be taken out, where
/// does it hang in the tree, and what value does it hold — `null` for an
/// element that is gone already, which no inverse puts back and which breaks
/// the block either way. [nextNode] is the tree's traversal successor.
///
/// Two elements share a block only when they are neighbours in the tree, so a
/// delete spanning a gap gives one block per side. A block goes back **whole**:
/// an element a peer wrote between two deleted ones while the delete was in
/// flight ends up in front of the restored block, not inside it.
List<FugueRestoreRun<K, V>> fugueRestoreRuns<K extends Object, V>({
  required Iterable<K> ids,
  required ({FugueElementID anchor, V value})? Function(K id) probe,
  required FugueElementID Function(FugueElementID node) nextNode,
}) {
  final runs = <FugueRestoreRun<K, V>>[];
  var items = <({K was, V value})>[];
  var runEnd = FugueElementID.nullID();

  void flush() {
    if (items.isEmpty) {
      return;
    }
    runs.add(
      FugueRestoreRun<K, V>(
        leftOrigin: runEnd,
        rightOrigin: nextNode(runEnd),
        items: items,
      ),
    );
    items = <({K was, V value})>[];
    runEnd = FugueElementID.nullID();
  }

  for (final id in ids) {
    final spot = probe(id);
    if (spot == null) {
      flush();
      continue;
    }
    if (items.isNotEmpty && nextNode(runEnd) != spot.anchor) {
      flush();
    }
    items.add((was: id, value: spot.value));
    runEnd = spot.anchor;
  }
  flush();

  return runs;
}
