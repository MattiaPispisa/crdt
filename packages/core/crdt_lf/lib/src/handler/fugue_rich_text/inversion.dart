// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'handler.dart';

extension _RichTextInversion on CRDTFugueRichTextHandler {
  // The value the key had before, piece by piece over the anchor space the
  // mark covers, tombstones included.
  List<Operation> _invertMark(_FugueRichTextMarkOperation operation) {
    final state = cachedOrComputedState();
    final at = _AnchorSlots(state._tree).at;
    const compare = _AnchorSlots.compare;

    final from = at(operation.start, start: true);
    final to = at(operation.end, start: false);
    if (from == null || to == null || compare(from, to) >= 0) {
      return const [];
    }

    final anchors = <_Slot, _Anchor>{from: operation.start, to: operation.end};
    final opens = <_Slot, List<_Mark>>{};
    final closes = <_Slot, List<_Mark>>{};
    for (final mark in state._marks.values) {
      if (mark.key != operation.key) {
        continue;
      }
      final start = at(mark.start, start: true);
      final end = at(mark.end, start: false);
      if (start == null || end == null || compare(start, end) >= 0) {
        continue;
      }
      if (compare(end, from) <= 0 || compare(start, to) >= 0) {
        continue;
      }
      (opens[compare(start, from) < 0 ? from : start] ??= []).add(mark);
      (closes[compare(end, to) > 0 ? to : end] ??= []).add(mark);
      if (compare(start, from) > 0) {
        anchors[start] = mark.start;
      }
      if (compare(end, to) < 0) {
        anchors[end] = mark.end;
      }
    }

    final points = anchors.keys.toList()..sort(compare);
    final active = SplayTreeSet<_Mark>(_Mark.byStamp);
    final inverses = <Operation>[];
    var pieceStart = from;
    Object? pieceValue;
    for (var i = 0; i + 1 < points.length; i++) {
      final point = points[i];
      closes[point]?.forEach(active.remove);
      opens[point]?.forEach(active.add);
      final value = active.isEmpty ? null : active.last.value;
      if (i == 0) {
        pieceValue = value;
        continue;
      }
      if (value == pieceValue) {
        continue;
      }
      inverses.add(
        _markOperation(
          operation.key,
          pieceValue,
          anchors[pieceStart]!,
          anchors[point]!,
        ),
      );
      pieceStart = point;
      pieceValue = value;
    }
    inverses.add(
      _markOperation(
        operation.key,
        pieceValue,
        anchors[pieceStart]!,
        anchors[to]!,
      ),
    );
    return inverses;
  }

  // An undone delete puts its elements back under new ids, outside the
  // anchors of the marks they had: a key is pinned on them again where the
  // gap they land in would give them another value. Only there, so undoing
  // the delete of plain text writes the text alone.
  List<Operation> _restoreFormats(
    FugueTextDeleteOperation operation,
    List<Operation> inserts,
  ) {
    final state = cachedOrComputedState();
    if (state._keys.isEmpty) {
      return const [];
    }
    final tree = state._tree;
    final resolved = state._resolved();
    // What the inserts put back, in their order.
    final was = [
      for (final item in operation.items)
        if (tree.isLive(item.nodeID) && tree.valueOf(item.nodeID) != null)
          item.nodeID,
    ];

    final marks = <Operation>[];
    var cursor = 0;
    for (final insert in inserts) {
      insert as FugueTextInsertOperation;
      final items = insert.items;
      final attributes = [
        for (var i = 0; i < items.length; i++)
          resolved.attributesAt(tree.liveIndexAfter(was[cursor + i])! - 1),
      ];
      cursor += items.length;
      final inherited = state._gapValues(insert.leftOrigin, insert.rightOrigin);
      for (final key in state._keys) {
        var runStart = 0;
        for (var i = 1; i <= items.length; i++) {
          final value = attributes[runStart][key];
          if (i < items.length && attributes[i][key] == value) {
            continue;
          }
          if (value != inherited[key]) {
            marks.add(
              _markOperation(
                key,
                value,
                _Anchor(_Anchor.before, items[runStart].id),
                _Anchor(_Anchor.after, items[i - 1].id),
              ),
            );
          }
          runStart = i;
        }
      }
    }
    return marks;
  }
}
