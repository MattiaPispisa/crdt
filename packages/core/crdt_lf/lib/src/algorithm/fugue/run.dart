import 'package:crdt_lf/src/algorithm/fugue/element_id.dart';

/// Which of a Fugue node's two child lists a child hangs in.
enum FugueSide {
  /// Left side
  left,

  /// Right side
  right,
}

/// A stretch of elements one peer wrote with consecutive counters, held in the
/// Fugue tree as a single node.
///
/// The run stands for the elements
/// `startID.counter … startID.counter + length - 1`. Element `i + 1` is by
/// construction the only right child of element `i`, so the run is a chain and
/// the tree can carry it as one node. Three consequences, and the tree keeps
/// all three true by splitting a run before it attaches anything to an inner
/// element:
///
/// - only the **first** element carries [leftChildren];
/// - only the **last** element carries [rightChildren];
/// - the elements in between carry no children at all.
///
/// A run mixes live elements and tombstones.
class FugueRun<T> {
  /// Creates a run over [values], with one [deleted] flag per value.
  ///
  /// [parentID] and [side] place the run's **first** element among its
  /// siblings, exactly as they placed a single node before runs existed.
  FugueRun({
    required this.startID,
    required this.parentID,
    required this.side,
    required List<T> values,
    required List<bool> deleted,
  })  : assert(values.length == deleted.length, 'one flag per value'),
        assert(values.isNotEmpty, 'a run holds at least one element'),
        _values = values,
        _deleted = deleted {
    for (final gone in _deleted) {
      if (!gone) {
        liveCount++;
      }
    }
  }

  /// The id of the run's first element.
  final FugueElementID startID;

  /// The parent of the run's **first** element.
  final FugueElementID parentID;

  /// Which side of [parentID] the run's first element sits on.
  final FugueSide side;

  final List<T> _values;
  final List<bool> _deleted;

  /// How many of the run's elements are still in the sequence.
  int liveCount = 0;

  List<FugueElementID>? _leftChildren;
  List<FugueElementID>? _rightChildren;

  /// How many elements the run holds, tombstones included.
  int get length => _values.length;

  /// The counter of the run's first element.
  int get startCounter => startID.counter!;

  /// The id of the run's last element.
  FugueElementID get lastID => idAt(length - 1);

  /// The id of the element at [offset].
  FugueElementID idAt(int offset) => offset == 0
      ? startID
      : FugueElementID(startID.replicaID, startCounter + offset);

  /// The value of the element at [offset]. A tombstone keeps its value.
  T valueAt(int offset) => _values[offset];

  /// Whether the element at [offset] has left the sequence.
  bool deletedAt(int offset) => _deleted[offset];

  /// Overwrites the value at [offset].
  void setValueAt(int offset, T value) {
    _values[offset] = value;
  }

  /// Takes the element at [offset] out of the sequence.
  ///
  /// Returns whether this call is what removed it, so the caller only reweighs
  /// the run when something changed.
  bool deleteAt(int offset) {
    if (_deleted[offset]) {
      return false;
    }
    _deleted[offset] = true;
    liveCount--;
    return true;
  }

  /// How many live elements sit strictly before [offset].
  int liveBefore(int offset) {
    var count = 0;
    for (var i = 0; i < offset; i++) {
      if (!_deleted[i]) {
        count++;
      }
    }
    return count;
  }

  /// The offset of the [liveOffset]-th live element, counting from `0`.
  ///
  /// The caller has already established the run holds that many live elements,
  /// which the assert restates.
  int offsetOfLive(int liveOffset) {
    var remaining = liveOffset;
    for (var i = 0; i < _deleted.length; i++) {
      if (_deleted[i]) {
        continue;
      }
      if (remaining == 0) {
        return i;
      }
      remaining--;
    }
    assert(false, 'run holds fewer than ${liveOffset + 1} live elements');
    return -1;
  }

  /// Adds [value] as the run's new last element, live.
  ///
  /// The caller has checked that the new element continues the counters and
  /// that nothing hangs off the current last element — see the merge rule in
  /// `FugueTree`.
  void append(T value) {
    _values.add(value);
    _deleted.add(false);
    liveCount++;
  }

  /// Cuts the run in two at [offset] and returns the new right half.
  ///
  /// This run keeps `0 … offset - 1`; the returned one takes `offset …` along
  /// with the right children, which belonged to the last element and still do.
  /// The new run hangs off this one's new last element as its only right child,
  /// which is the relation those two elements already had — so the split is
  /// invisible to the sequence, and to every id in it.
  ///
  /// The caller links the halves and updates the positional index.
  FugueRun<T> splitAt(int offset) {
    assert(offset > 0 && offset < length, 'split point inside the run');
    final tail = FugueRun<T>(
      startID: idAt(offset),
      parentID: idAt(offset - 1),
      side: FugueSide.right,
      values: _values.sublist(offset),
      deleted: _deleted.sublist(offset),
    ).._rightChildren = _rightChildren;

    _values.removeRange(offset, _values.length);
    _deleted.removeRange(offset, _deleted.length);
    liveCount -= tail.liveCount;
    _rightChildren = null;
    return tail;
  }

  /// The runs hanging off the **first** element's left side, by start id, in
  /// id order.
  ///
  /// Read-only: the empty case is a shared constant. Use [insertChild] to add
  /// one.
  List<FugueElementID> get leftChildren =>
      _leftChildren ?? const <FugueElementID>[];

  /// The runs hanging off the **last** element's right side, by start id, in
  /// id order.
  ///
  /// Read-only: the empty case is a shared constant. Use [insertChild] to add
  /// one.
  List<FugueElementID> get rightChildren =>
      _rightChildren ?? const <FugueElementID>[];

  /// Puts the run starting at [id] among the children on [side], at [index].
  void insertChild(
    FugueElementID id, {
    required FugueSide side,
    required int index,
  }) {
    if (side == FugueSide.left) {
      (_leftChildren ??= <FugueElementID>[]).insert(index, id);
    } else {
      (_rightChildren ??= <FugueElementID>[]).insert(index, id);
    }
  }

  @override
  String toString() => 'FugueRun($startID, length: $length, live: $liveCount, '
      'parent: $parentID, side: $side)';
}
