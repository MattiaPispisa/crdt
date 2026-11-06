// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'handler.dart';

/// State of the [CRDTFugueRichTextHandler]: the text and its marks.
class RichTextState extends FugueState<String, List<RichTextSpan>> {
  RichTextState._(this._tree) : super(_tree, _unprojected);

  /// Creates an empty state.
  factory RichTextState.empty() => RichTextState._(FugueTree<String>.empty());

  final FugueTree<String> _tree;

  final Map<OperationId, _Mark> _marks = {};

  final Set<FugueElementID> _afterAnchored = {};

  final Set<String> _keys = {};

  final Map<FugueElementID, List<_Mark>> _anchored = {};

  final List<_Mark> _textAnchored = [];

  _MarkIndex? _markIndex;

  _ResolvedMarks? _resolvedCache;

  List<RichTextSpan>? _spansCache;

  String? _textCache;

  _EmbedTable _embeds = _EmbedTable();

  // The spans need the marks, which the tree alone does not hold.
  static List<RichTextSpan> _unprojected(FugueTree<String> tree) =>
      throw UnsupportedError('read the spans from RichTextState');

  bool _addMark(_FugueRichTextMarkOperation operation) {
    final stamp = operation.stamp!;
    if (_marks.containsKey(stamp)) {
      return false;
    }
    _putMark(
      _Mark(
        stamp: stamp,
        key: operation.key,
        value: operation.value,
        start: operation.start,
        end: operation.end,
      ),
    );
    return true;
  }

  void _putMark(_Mark mark) {
    _marks[mark.stamp] = mark;
    _keys.add(mark.key);
    _markIndex?.add(mark);
    for (final anchor in [mark.start, mark.end]) {
      if (anchor.side == _Anchor.after) {
        _afterAnchored.add(anchor.id!);
      }
    }
    final startId = mark.start.id;
    final endId = mark.end.id;
    if (startId == null || endId == null) {
      _textAnchored.add(mark);
    }
    if (startId != null) {
      (_anchored[startId] ??= []).add(mark);
    }
    if (endId != null && endId != startId) {
      (_anchored[endId] ??= []).add(mark);
    }
    _spansCache = null;
    final resolved = _resolvedCache;
    if (resolved == null) {
      return;
    }
    final from = mark.start.liveStart(_tree);
    final to = mark.end.liveEnd(_tree, _tree.liveLength);
    if (from != null && to != null) {
      resolved.patch(mark, from, to);
    }
  }

  void _treeChanged(Operation operation, SequenceDelta<String>? delta) {
    if (operation is _FugueRichTextEmbedOperation) {
      _embeds.inserted(operation);
    } else if (operation is FugueTextDeleteOperation) {
      _embeds.deletedIn(operation);
    }
    _textCache = null;
    _spansCache = null;
    final resolved = _resolvedCache;
    // An update keeps every element in place, so the runs stay right.
    if (resolved == null ||
        delta == null ||
        delta.isEmpty ||
        operation is FugueTextUpdateOperation) {
      return;
    }
    if (operation is FugueTextDeleteOperation) {
      resolved.remove(delta);
    } else if (!_shiftInsert(
      resolved,
      operation as FugueTextInsertOperation,
      delta,
    )) {
      _resolvedCache = null;
    }
  }

  // Past this many tombstones, resolving every mark again is the cheaper way.
  int get _walkLimit => 256 + _marks.length;

  // Moves the resolved runs for a plain insert and gives the new runes the
  // marks around them; `false` when it cannot tell, and the runs are dropped.
  bool _shiftInsert(
    _ResolvedMarks resolved,
    FugueTextInsertOperation operation,
    SequenceDelta<String> delta,
  ) {
    final ops = delta.ops;
    final head = ops.first;
    final at = head is SeqRetain<String> ? head.count : 0;
    final insert = ops[head is SeqRetain<String> ? 1 : 0];
    final items = operation.items;
    if (insert is! SeqInsert<String> ||
        insert.values.length != items.length ||
        resolved.length + items.length != _tree.liveLength ||
        items.any((item) => _anchored.containsKey(item.id))) {
      return false;
    }

    final walk = <FugueElementID>[];
    var node = FugueElementID.nullID();
    if (at > 0) {
      node = _tree.findNodeAtPosition(at - 1);
      walk.add(node);
    }
    node = _tree.findNextNode(node);
    while (node != items.first.id) {
      if (node.isNull || _tree.isLive(node) || walk.length > _walkLimit) {
        return false;
      }
      walk.add(node);
      node = _tree.findNextNode(node);
    }
    final block = walk.length;
    walk.add(node);
    node = _tree.findNextNode(items.last.id);
    while (!node.isNull && !_tree.isLive(node)) {
      if (walk.length > _walkLimit) {
        return false;
      }
      walk.add(node);
      node = _tree.findNextNode(node);
    }
    if (node.isNull != (at == resolved.length)) {
      return false;
    }
    if (!node.isNull) {
      walk.add(node);
    }

    final winners = _winnersAround(
      walk,
      low: 3 * block,
      high: 3 * block + 2,
      leftIndex: at - 1,
      left: at > 0 ? resolved.winnersAt(at - 1) : null,
      right: node.isNull ? null : resolved.winnersAt(at),
    );
    resolved.insert(at, items.length, winners);
    return true;
  }

  // The value each key gives to text put between [left], a live element, and
  // its successor [right].
  Map<String, Object?> _gapValues(FugueElementID left, FugueElementID right) {
    assert(_tree.isLive(left), 'a restored run hangs off a live element');
    final index = _tree.liveIndexAfter(left)! - 1;
    final walk = [left];
    var node = right;
    while (!node.isNull && !_tree.isLive(node)) {
      walk.add(node);
      node = _tree.findNextNode(node);
    }
    if (!node.isNull) {
      walk.add(node);
    }
    final resolved = _resolved();
    final winners = _winnersAround(
      walk,
      low: 2,
      high: 3,
      leftIndex: index,
      left: resolved.winnersAt(index),
      right: node.isNull ? null : resolved.winnersAt(index + 1),
    );
    return {
      for (final entry in winners.entries) entry.key: entry.value.value,
    };
  }

  // The newest mark of each key that covers the slots [low, high] of [walk]:
  // the live elements around them and the tombstones between. A mark covering
  // them either covers a live neighbour, where [left] or [right] holds the
  // newest one, or has an anchor in [walk]. A key neither neighbour tells is
  // read from all its marks.
  Map<String, _Mark> _winnersAround(
    List<FugueElementID> walk, {
    required int low,
    required int high,
    required int leftIndex,
    required Map<String, _Mark>? left,
    required Map<String, _Mark>? right,
  }) {
    final ordinals = <FugueElementID, int>{
      for (var i = 0; i < walk.length; i++) walk[i]: i,
    };
    final far = 3 * walk.length;

    int? slot(_Anchor anchor, {required bool start}) {
      final id = anchor.id;
      if (id == null) {
        return start ? -1 : far;
      }
      final ordinal = ordinals[id];
      if (ordinal != null) {
        return anchor.side == _Anchor.before ? 3 * ordinal : 3 * ordinal + 2;
      }
      final after = _tree.liveIndexAfter(id);
      if (after == null) {
        return null;
      }
      return after <= leftIndex ? -1 : far;
    }

    bool covers(_Mark mark) {
      final start = slot(mark.start, start: true);
      final end = slot(mark.end, start: false);
      return start != null && end != null && start <= low && end >= high;
    }

    final found = <String, _Mark>{};
    void consider(_Mark mark) {
      if (!covers(mark)) {
        return;
      }
      final current = found[mark.key];
      if (current == null || _Mark.byStamp(current, mark) < 0) {
        found[mark.key] = mark;
      }
    }

    for (final id in walk) {
      _anchored[id]?.forEach(consider);
    }
    if (left == null || right == null) {
      _textAnchored.forEach(consider);
    }

    final winners = <String, _Mark>{};
    final unknown = <String>{};
    for (final key in {...?left?.keys, ...?right?.keys, ...found.keys}) {
      final before = left?[key];
      final after = right?[key];
      final _Mark? side;
      if (before == null || covers(before)) {
        side = before;
      } else if (after == null || covers(after)) {
        side = after;
      } else {
        unknown.add(key);
        continue;
      }
      var best = found[key];
      if (side != null && (best == null || _Mark.byStamp(best, side) < 0)) {
        best = side;
      }
      if (best != null) {
        winners[key] = best;
      }
    }
    if (unknown.isNotEmpty) {
      for (final mark in _marks.values) {
        if (!unknown.contains(mark.key) || !covers(mark)) {
          continue;
        }
        final current = winners[mark.key];
        if (current == null || _Mark.byStamp(current, mark) < 0) {
          winners[mark.key] = mark;
        }
      }
    }
    return winners;
  }

  _ResolvedMarks _resolved() =>
      _resolvedCache ??= _ResolvedMarks.resolve(_tree, _marks.values);

  // Built on first use: only an undo reads it.
  _MarkIndex _indexed() => _markIndex ??= _MarkIndex(_marks.values);

  String _text() => _textCache ??= _tree.values().join();

  List<RichTextSpan> _spans() {
    final cached = _spansCache;
    if (cached != null) {
      return cached;
    }
    final runes = _tree.values();
    final runs = _resolved().runsIn(0, runes.length);
    // Only a text with embeds pays for the walk over the element ids.
    if (_embeds.live.isEmpty) {
      return _spansCache = List.unmodifiable(<RichTextSpan>[
        for (final run in runs)
          RichTextSpan(
            runes.sublist(run.start, run.end).join(),
            run.attributes,
          ),
      ]);
    }

    final embeds = <({int index, Map<String, Object?> data})>[];
    var index = 0;
    _tree.forEachLiveNode((id, _) {
      final embed = _embeds.live[id];
      if (embed != null) {
        embeds.add((index: index, data: embed.data));
      }
      index++;
    });

    final result = <RichTextSpan>[];
    var next = 0;
    for (final run in runs) {
      var start = run.start;
      while (next < embeds.length && embeds[next].index < run.end) {
        final at = embeds[next].index;
        if (start < at) {
          result.add(
            RichTextSpan(runes.sublist(start, at).join(), run.attributes),
          );
        }
        result.add(RichTextSpan.embed(embeds[next].data, run.attributes));
        start = at + 1;
        next++;
      }
      if (start < run.end) {
        result.add(
          RichTextSpan(runes.sublist(start, run.end).join(), run.attributes),
        );
      }
    }
    return _spansCache = List.unmodifiable(result);
  }
}

class _EmbedTable {
  final Map<FugueElementID, _Embed> live = {};

  void inserted(_FugueRichTextEmbedOperation operation) {
    live[operation.element] = _Embed(operation.data, operation.stamp!);
  }

  // The data leaves with the delete: the undo copies it when it captures.
  void deletedIn(FugueTextDeleteOperation operation) {
    if (live.isEmpty) {
      return;
    }
    for (final item in operation.items) {
      live.remove(item.nodeID);
    }
  }

  bool update(_FugueRichTextEmbedUpdateOperation operation) {
    final current = live[operation.element];
    final stamp = operation.stamp!;
    if (current == null || stamp.compareTo(current.stamp) <= 0) {
      return false;
    }
    live[operation.element] = _Embed(operation.data, stamp);
    return true;
  }

  // The update without the items that name an embed, or null when none is
  // left. A deleted embed needs no check: the tree refuses an update on a
  // tombstone.
  FugueTextUpdateOperation? withoutEmbeds(FugueTextUpdateOperation operation) {
    if (live.isEmpty) {
      return operation;
    }
    final items = [
      for (final item in operation.items)
        if (!live.containsKey(item.nodeID)) item,
    ];
    if (items.length == operation.items.length) {
      return operation;
    }
    if (items.isEmpty) {
      return null;
    }
    return FugueTextUpdateOperation(
      items: items,
      id: operation.id,
      type: operation.type,
    )..stamp = operation.stamp;
  }
}

final class _SequenceCollector implements DeltaSink<Object?> {
  SequenceDelta<String>? delta;

  @override
  void add(Object? delta) {
    final next = delta! as SequenceDelta<String>;
    final current = this.delta;
    this.delta = current == null ? next : current.compose(next);
  }
}
