// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'handler.dart';

typedef _PlacedMark = ({_Mark mark, _Slot start, _Slot end});

// Elements never move and tombstones stay, so two placed anchors keep their
// order for good while their slots shift: the index holds marks, never slots.
class _MarkIndex {
  _MarkIndex(Iterable<_Mark> marks) : _keys = {} {
    marks.forEach(add);
  }

  final Map<String, _KeyMarks> _keys;

  void add(_Mark mark) => (_keys[mark.key] ??= _KeyMarks()).add(mark);

  List<_PlacedMark> overlapping(
    String key,
    _AnchorSlots slots, {
    required _Slot from,
    required _Slot to,
  }) =>
      _keys[key]?.overlapping(slots, from: from, to: to) ?? const [];
}

class _KeyMarks {
  _KeyMarks()
      : _pending = [],
        _blocks = [],
        _count = 0;

  final List<_Mark> _pending;

  final List<_MarkBlock> _blocks;

  int _count;

  // Each block costs two anchor lookups a query, more than a few marks do.
  static const int _minBlock = 16;

  int get _blockSize => max(_minBlock, sqrt(_count).ceil());

  void add(_Mark mark) => _pending.add(mark);

  List<_PlacedMark> overlapping(
    _AnchorSlots slots, {
    required _Slot from,
    required _Slot to,
  }) {
    _settle(slots);
    final found = <_PlacedMark>[];
    for (final block in _blocks) {
      if (_AnchorSlots.compare(block.first(slots), to) >= 0) {
        break;
      }
      if (_AnchorSlots.compare(block.farthestEnd(slots), from) <= 0) {
        continue;
      }
      for (final mark in block.marks) {
        final start = mark.startIn(slots);
        if (_AnchorSlots.compare(start, to) >= 0) {
          break;
        }
        final end = mark.endIn(slots);
        if (_AnchorSlots.compare(end, from) > 0) {
          found.add((mark: mark, start: start, end: end));
        }
      }
    }
    return found;
  }

  void _settle(_AnchorSlots slots) {
    if (_pending.isEmpty) {
      return;
    }
    final placed = <({_Mark mark, _Slot start})>[];
    final unplaced = <_Mark>[];
    for (final mark in _pending) {
      final start = slots.at(mark.start, start: true);
      final end = slots.at(mark.end, start: false);
      if (start == null || end == null) {
        // Its element may still arrive.
        unplaced.add(mark);
      } else if (_AnchorSlots.compare(start, end) < 0) {
        placed.add((mark: mark, start: start));
      }
    }
    _pending
      ..clear()
      ..addAll(unplaced);

    if (_blocks.isEmpty) {
      _build(placed, slots);
    } else {
      for (final entry in placed) {
        _insert(entry.mark, entry.start, slots);
      }
    }
  }

  void _build(List<({_Mark mark, _Slot start})> placed, _AnchorSlots slots) {
    placed.sort((a, b) => _AnchorSlots.compare(a.start, b.start));
    final sorted = [for (final entry in placed) entry.mark];
    _count = sorted.length;
    final size = _blockSize;
    for (var i = 0; i < sorted.length; i += size) {
      final end = min(i + size, sorted.length);
      _blocks.add(_MarkBlock(sorted.sublist(i, end), slots));
    }
  }

  void _insert(_Mark mark, _Slot start, _AnchorSlots slots) {
    // Past its equals: the first start after this one.
    int order(_Mark other, _Slot target) =>
        _AnchorSlots.compare(other.startIn(slots), target) > 0 ? 1 : -1;

    final after = _blocks.lowerBoundBy(
      start,
      (block, target) => order(block.marks.first, target),
    );
    final index = max(after - 1, 0);
    final block = _blocks[index];
    final position = block.marks.lowerBoundBy(start, order);
    block.insert(position, mark, slots);
    _count++;
    if (block.marks.length > 2 * _blockSize) {
      _blocks.insert(index + 1, block.split(slots));
    }
  }
}

class _MarkBlock {
  _MarkBlock(this.marks, _AnchorSlots slots) : _farthest = marks.first {
    _findFarthest(slots);
  }

  // In order of start.
  final List<_Mark> marks;

  // Ends are not sorted: this one says if the whole block ends too early.
  _Mark _farthest;

  _Slot first(_AnchorSlots slots) => marks.first.startIn(slots);

  _Slot farthestEnd(_AnchorSlots slots) => _farthest.endIn(slots);

  void insert(int index, _Mark mark, _AnchorSlots slots) {
    marks.insert(index, mark);
    if (_AnchorSlots.compare(mark.endIn(slots), farthestEnd(slots)) > 0) {
      _farthest = mark;
    }
  }

  _MarkBlock split(_AnchorSlots slots) {
    final half = marks.length ~/ 2;
    final tail = _MarkBlock(marks.sublist(half), slots);
    marks.length = half;
    _findFarthest(slots);
    return tail;
  }

  void _findFarthest(_AnchorSlots slots) {
    _farthest = marks.first;
    for (final mark in marks) {
      if (_AnchorSlots.compare(mark.endIn(slots), farthestEnd(slots)) > 0) {
        _farthest = mark;
      }
    }
  }
}

extension on _Mark {
  _Slot startIn(_AnchorSlots slots) => slots.at(start, start: true)!;

  _Slot endIn(_AnchorSlots slots) => slots.at(end, start: false)!;
}
