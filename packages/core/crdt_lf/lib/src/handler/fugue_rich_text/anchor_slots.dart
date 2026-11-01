// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'handler.dart';

// The anchor space of the tree, tombstones included: before x, x, after x.
// Live element i is (2i + 1, side); the k-th tombstone before live element g
// is (2g, 3k + side).
typedef _Slot = (int, int);

class _AnchorSlots {
  _AnchorSlots(this._tree);

  final FugueTree<String> _tree;

  final Map<int, Map<FugueElementID, int>> _gaps = {};

  static int compare(_Slot a, _Slot b) =>
      a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2);

  _Slot? at(_Anchor anchor, {required bool start}) {
    final id = anchor.id;
    if (id == null) {
      return start ? (-1, 0) : (2 * _tree.liveLength + 1, 0);
    }
    final after = _tree.liveIndexAfter(id);
    if (after == null) {
      return null;
    }
    final side = anchor.side == _Anchor.before ? 0 : 2;
    if (_tree.isLive(id)) {
      return (2 * after - 1, side);
    }
    final gap = _gaps[after] ??= _walkGap(after);
    return (2 * after, 3 * gap[id]! + side);
  }

  Map<FugueElementID, int> _walkGap(int live) {
    final gap = <FugueElementID, int>{};
    var node = _tree.findNextNode(
      live == 0 ? FugueElementID.nullID() : _tree.findNodeAtPosition(live - 1),
    );
    while (!node.isNull && !_tree.isLive(node)) {
      gap[node] = gap.length;
      node = _tree.findNextNode(node);
    }
    return gap;
  }
}
