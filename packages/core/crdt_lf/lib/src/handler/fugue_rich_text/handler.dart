// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:collection';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_sequence_apply.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_sequence_handler.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_snapshot.dart';

part 'mark.dart';
part 'operation.dart';

enum MarkExpand {
  none,
  before,
  after,
  both,
}

base class CRDTFugueRichTextHandler
    extends FugueSequenceHandler<String, List<RichTextSpan>, RichTextState>
    with DeltaProvider<List<RichTextSpan>, RichTextDelta> {
  CRDTFugueRichTextHandler(super.doc, super.id)
      : super(spec: CRDTFugueRichTextHandler.spec);

  static const String _handlerType = 'CRDTFugueRichTextHandler';

  static const HandlerSpec<CRDTFugueRichTextHandler> spec = HandlerSpec(
    _handlerType,
    CRDTFugueRichTextHandler.new,
    formats: _formats,
  );

  static const int _kindMark = 4;

  static const HandlerFormats _formats = HandlerFormats(
    operationKinds: {
      OperationType.kindInsert,
      OperationType.kindDelete,
      OperationType.kindUpdate,
      _kindMark,
    },
    blobVersions: BlobVersionRange.single(FugueSnapshot.version),
  );

  late final OperationType markType = OperationType.custom(
    this,
    kind: _kindMark,
    name: 'mark',
    stamped: true,
  );

  @override
  late final OperationDecoders operationDecoders = {
    OperationType.kindInsert: (body) =>
        _FugueRichTextInsertOperation.fromBodyBytes(this, body),
    OperationType.kindDelete: (body) =>
        _FugueRichTextDeleteOperation.fromBodyBytes(this, body),
    OperationType.kindUpdate: (body) =>
        _FugueRichTextUpdateOperation.fromBodyBytes(this, body),
    _kindMark: (body) => _FugueRichTextMarkOperation.fromBodyBytes(this, body),
  };

  void insert(
    int index,
    String text, {
    Map<String, Object?> attributes = const {},
  }) {
    if (text.isEmpty) {
      return;
    }
    for (final value in attributes.values) {
      _MarkValue.check(value);
    }

    final (leftOrigin, rightOrigin) = _insertOrigins(index);

    final items = <_FugueInsertItem>[
      for (final rune in text.runes)
        _FugueInsertItem(
          id: FugueElementID(doc.peerId, nextCounter()),
          text: String.fromCharCode(rune),
        ),
    ];

    final insert = _FugueRichTextInsertOperation.fromHandler(
      this,
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
      items: items,
    );

    if (attributes.isEmpty) {
      doc.registerOperation(insert);
      return;
    }

    doc.runInTransaction(() {
      doc.registerOperation(insert);
      _markInserted(items, attributes);
    });
  }

  // Peritext's rule: among the tombstones at the insert position, go after the
  // last one whose "after" anchor starts or ends a mark, else before them all.
  (FugueElementID, FugueElementID) _insertOrigins(int index) {
    final left = originBefore(index);
    final right = nodeAfter(left);
    final state = cachedOrComputedState();
    final anchored = state._afterAnchored;
    if (anchored.isEmpty) {
      return (left, right);
    }

    final tree = state._tree;
    var origins = (left, right);
    var node = right;
    while (!node.isNull && !tree.isLive(node)) {
      final next = nodeAfter(node);
      if (anchored.contains(node)) {
        origins = (node, next);
      }
      node = next;
    }
    return origins;
  }

  // Inline runs expand after their end; a '\n' gets block anchors.
  void _markInserted(
    List<_FugueInsertItem> items,
    Map<String, Object?> attributes,
  ) {
    var runStart = 0;
    for (var i = 0; i <= items.length; i++) {
      final atBreak = i == items.length || items[i].text == '\n';
      if (!atBreak) {
        continue;
      }
      if (runStart < i) {
        final first = items[runStart].id;
        final last = items[i - 1].id;
        for (final entry in attributes.entries) {
          _markIds(
            first: first,
            last: last,
            key: entry.key,
            value: entry.value,
            expand: MarkExpand.after,
          );
        }
      }
      if (i < items.length) {
        final newline = items[i].id;
        for (final entry in attributes.entries) {
          _markIds(
            first: newline,
            last: newline,
            key: entry.key,
            value: entry.value,
            expand: MarkExpand.none,
            block: true,
          );
        }
      }
      runStart = i + 1;
    }
  }

  void format(
    int index,
    int length,
    String key,
    Object? value, {
    MarkExpand expand = MarkExpand.after,
  }) {
    _MarkValue.check(value);
    final from = index < 0 ? 0 : index;
    final to = index + length > this.length ? this.length : index + length;
    if (to <= from) {
      return;
    }

    final first = nodeAt(from);
    final last = nodeAt(to - 1);
    final block = expand == MarkExpand.none &&
        to - from == 1 &&
        cachedOrComputedState()._tree.valueOf(first) == '\n';
    _markIds(
      first: first,
      last: last,
      key: key,
      value: value,
      expand: expand,
      block: block,
    );
  }

  void _markIds({
    required FugueElementID first,
    required FugueElementID last,
    required String key,
    required Object? value,
    required MarkExpand expand,
    bool block = false,
  }) {
    final state = cachedOrComputedState();
    final tree = state._tree;
    final from = tree.liveIndexAfter(first)! - 1;
    final to = tree.liveIndexAfter(last)!;
    if (state._resolved().isRedundant(from, to, key, value)) {
      return;
    }

    final sides = value == null && expand == MarkExpand.none && !block
        ? MarkExpand.both
        : expand;
    final expandsStart = sides == MarkExpand.before || sides == MarkExpand.both;
    final expandsEnd = sides == MarkExpand.after || sides == MarkExpand.both;

    final _Anchor start;
    if (expandsStart) {
      final previous = originBefore(from);
      start = previous.isNull
          ? const _Anchor.text()
          : _Anchor(_Anchor.after, previous);
    } else {
      start = _Anchor(_Anchor.before, first);
    }

    final _Anchor end;
    if (expandsEnd) {
      final next = nodeAfter(last);
      end = next.isNull ? const _Anchor.text() : _Anchor(_Anchor.before, next);
    } else {
      end = _Anchor(_Anchor.after, last);
    }

    doc.registerOperation(
      _FugueRichTextMarkOperation.fromHandler(
        this,
        key: key,
        value: value,
        start: start,
        end: end,
      ),
    );
  }

  Map<String, Object?> attributesAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    return cachedOrComputedState()._resolved().attributesAt(index);
  }

  @override
  List<RichTextSpan> get value => cachedOrComputedState()._spans();

  String get text => cachedOrComputedState()._text();

  void update(int index, String text) {
    if (text.isEmpty) {
      return;
    }

    final runes = text.runes.toList();
    final items = <_FugueUpdateItem>[];
    for (var i = 0; i < runes.length; i++) {
      final nodeID = nodeAt(index + i);
      if (nodeID.isNull) {
        break;
      }
      items.add(
        _FugueUpdateItem(nodeID: nodeID, text: String.fromCharCode(runes[i])),
      );
    }

    if (items.isEmpty) {
      return;
    }

    doc.registerOperation(
      _FugueRichTextUpdateOperation.fromHandler(this, items: items),
    );
  }

  void change(String newText) {
    final diff = myersDiff(text, newText);
    var offset = 0;
    for (final segment in diff) {
      switch (segment.op) {
        case DiffOp.equal:
          break;
        case DiffOp.insert:
          insert(segment.oldStart + offset, segment.text);
          offset += segment.newEnd - segment.newStart;
        case DiffOp.remove:
          final count = segment.oldEnd - segment.oldStart;
          delete(segment.oldStart + offset, count);
          offset -= count;
      }
    }
  }

  int get length => elementCount;

  @override
  RichTextState createEmptyState() => RichTextState.empty();

  @override
  RichTextState computeState() {
    final state = super.computeState();
    final snapshot = lastSnapshot();
    if (snapshot != null) {
      _MarksSection.read(snapshot).forEach(state._putMark);
    }
    for (final operation in operations()) {
      if (operation is _FugueRichTextMarkOperation) {
        state._addMark(operation);
      }
    }
    return state;
  }

  @override
  void applyOperation(
    RichTextState state,
    Operation operation, {
    DeltaSink<Object?>? sink,
  }) {
    if (operation is _FugueRichTextMarkOperation) {
      if (sink == null) {
        state._addMark(operation);
        return;
      }
      final before = state._resolved();
      if (!state._addMark(operation)) {
        sink.add(const RichTextDelta.empty());
        return;
      }
      sink.add(_markDelta(state, operation, before));
      return;
    }

    if (sink == null) {
      super.applyOperation(state, operation);
      state._treeChanged();
      return;
    }
    final collected = _SequenceCollector();
    super.applyOperation(state, operation, sink: collected);
    state._treeChanged();
    sink.add(_richDelta(state, collected.delta));
  }

  // The tree half of the delta, with the attributes the inserted text has
  // once the operation is in.
  RichTextDelta _richDelta(RichTextState state, SequenceDelta<String>? delta) {
    if (delta == null || delta.isEmpty) {
      return const RichTextDelta.empty();
    }
    final resolved = state._resolved();
    final ops = <RichTextOp>[];
    var out = 0;
    for (final op in delta.ops) {
      switch (op) {
        case SeqRetain<String>():
          ops.add(RichTextRetain(op.count));
          out += op.count;
        case SeqDelete<String>():
          ops.add(RichTextDelete(op.count));
        case SeqInsert<String>():
          final end = out + op.values.length;
          for (final run in resolved.runsIn(out, end)) {
            ops.add(
              RichTextInsert(
                op.values.sublist(run.start - out, run.end - out).join(),
                run.attributes,
              ),
            );
          }
          out = end;
        case SeqMove<String>():
          throw UnsupportedError('a rich text never moves an element');
      }
    }
    return RichTextDelta(ops);
  }

  // The covered places whose value for the key of the mark moved.
  RichTextDelta _markDelta(
    RichTextState state,
    _FugueRichTextMarkOperation operation,
    _ResolvedMarks before,
  ) {
    final tree = state._tree;
    final from = operation.start.liveStart(tree);
    final to = operation.end.liveEnd(tree, tree.liveLength);
    if (from == null || to == null || from >= to) {
      return const RichTextDelta.empty();
    }

    final key = operation.key;
    final was = before.keyRuns(key, from, to);
    final now = state._resolved().keyRuns(key, from, to);
    final ops = <RichTextOp>[];
    var cursor = 0;
    var position = from;
    var i = 0;
    var j = 0;
    while (position < to) {
      final end = was[i].end < now[j].end ? was[i].end : now[j].end;
      if (was[i].value != now[j].value) {
        ops
          ..add(RichTextRetain(position - cursor))
          ..add(RichTextRetain(end - position, {key: now[j].value}));
        cursor = end;
      }
      position = end;
      if (was[i].end == end) {
        i++;
      }
      if (now[j].end == end) {
        j++;
      }
    }
    return RichTextDelta(ops);
  }

  @override
  void applyToTree(
    FugueTree<String> tree,
    Operation operation, {
    DeltaSink<Object?>? sink,
  }) {
    // Marks live beside the tree: [applyOperation] and [computeState] fold
    // them.
    if (operation is _FugueRichTextMarkOperation) {
      return;
    }
    if (!applyFugueSequenceOperation<String>(tree, operation, sink: sink)) {
      sink?.add(const SequenceDelta<String>.empty());
    }
  }

  @override
  List<RichTextSpan> applyDelta(
    List<RichTextSpan> base,
    RichTextDelta delta,
  ) =>
      delta.apply(base);

  @override
  List<Operation> invert(Operation operation) {
    if (operation is _FugueRichTextMarkOperation) {
      return _invertMark(operation);
    }
    final inverses = super.invert(operation);
    if (operation is _FugueRichTextDeleteOperation && inverses.isNotEmpty) {
      return [...inverses, ..._restoreFormats(operation, inverses)];
    }
    return inverses;
  }

  // The value the key had before, piece by piece over the anchor space the
  // mark covers, tombstones included.
  List<Operation> _invertMark(_FugueRichTextMarkOperation operation) {
    final state = cachedOrComputedState();
    final order = <FugueElementID, int>{};
    var count = 0;
    state._tree.forEachNode((id, _, {required deleted}) {
      order[id] = count++;
    });
    // Before x, x, after x: three slots per element.
    final last = 3 * count;
    int? at(_Anchor anchor, {required bool start}) {
      final id = anchor.id;
      if (id == null) {
        return start ? -1 : last;
      }
      final index = order[id];
      if (index == null) {
        return null;
      }
      return anchor.side == _Anchor.before ? 3 * index : 3 * index + 2;
    }

    final from = at(operation.start, start: true);
    final to = at(operation.end, start: false);
    if (from == null || to == null || from >= to) {
      return const [];
    }

    final anchors = <int, _Anchor>{from: operation.start, to: operation.end};
    final opens = <int, List<_Mark>>{};
    final closes = <int, List<_Mark>>{};
    for (final mark in state._marks.values) {
      if (mark.key != operation.key) {
        continue;
      }
      final start = at(mark.start, start: true);
      final end = at(mark.end, start: false);
      if (start == null || end == null || start >= end) {
        continue;
      }
      if (end <= from || start >= to) {
        continue;
      }
      (opens[start < from ? from : start] ??= []).add(mark);
      (closes[end > to ? to : end] ??= []).add(mark);
      if (start > from) {
        anchors[start] = mark.start;
      }
      if (end < to) {
        anchors[end] = mark.end;
      }
    }

    final points = anchors.keys.toList()..sort();
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
  // anchors of the marks they had: every known key is pinned on them again.
  List<Operation> _restoreFormats(
    _FugueRichTextDeleteOperation operation,
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
      final items = (insert as _FugueRichTextInsertOperation).items;
      final attributes = [
        for (var i = 0; i < items.length; i++)
          resolved.attributesAt(tree.liveIndexAfter(was[cursor + i])! - 1),
      ];
      cursor += items.length;
      for (final key in state._keys) {
        var runStart = 0;
        for (var i = 1; i <= items.length; i++) {
          final value = attributes[runStart][key];
          if (i < items.length && attributes[i][key] == value) {
            continue;
          }
          marks.add(
            _markOperation(
              key,
              value,
              _Anchor(_Anchor.before, items[runStart].id),
              _Anchor(_Anchor.after, items[i - 1].id),
            ),
          );
          runStart = i;
        }
      }
    }
    return marks;
  }

  _FugueRichTextMarkOperation _markOperation(
    String key,
    Object? value,
    _Anchor start,
    _Anchor end,
  ) =>
      _FugueRichTextMarkOperation.fromHandler(
        this,
        key: key,
        value: value,
        start: start,
        end: end,
      );

  @override
  Operation prepareInverse(Operation operation) {
    if (operation is! _FugueRichTextMarkOperation) {
      return super.prepareInverse(operation);
    }
    if (!hasRebuiltIdentities) {
      return operation;
    }
    final start = _latestAnchor(operation.start);
    final end = _latestAnchor(operation.end);
    if (start == operation.start && end == operation.end) {
      return operation;
    }
    return _markOperation(operation.key, operation.value, start, end);
  }

  // A restored element sits right after the one it stands for, so an anchor
  // on the old one moves to the new one.
  _Anchor _latestAnchor(_Anchor anchor) {
    final id = anchor.id;
    if (id == null) {
      return anchor;
    }
    final latest = latestOf(id);
    return latest == id ? anchor : _Anchor(anchor.side, latest);
  }

  @override
  Iterable<FugueElementID> producedElementIds(Operation operation) sync* {
    if (operation is _FugueRichTextInsertOperation) {
      for (final item in operation.items) {
        yield item.id;
      }
    }
  }

  @override
  Operation buildDeleteOperation(List<FugueElementID> nodeIDs) {
    return _FugueRichTextDeleteOperation.fromHandler(
      this,
      items: nodeIDs.map((id) => _FugueDeleteItem(nodeID: id)).toList(),
    );
  }

  @override
  Operation buildInsertOperation({
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
    required List<({FugueElementID id, String value})> items,
  }) {
    return _FugueRichTextInsertOperation.fromHandler(
      this,
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
      items: [
        for (final item in items)
          _FugueInsertItem(id: item.id, text: item.value),
      ],
    );
  }

  @override
  Operation buildUpdateOperation(
    List<({FugueElementID nodeID, String value})> items,
  ) {
    return _FugueRichTextUpdateOperation.fromHandler(
      this,
      items: [
        for (final item in items)
          _FugueUpdateItem(nodeID: item.nodeID, text: item.value),
      ],
    );
  }

  @override
  Uint8List encodeRun(List<String> values) => Wtf8.encodeAll(values);

  @override
  List<String> decodeRun(Uint8List blob, int length) =>
      Wtf8.decodeCodePoints(blob);

  @override
  Uint8List getSnapshotState() {
    final fugue = super.getSnapshotState();
    final marks = _MarksSection.write(cachedOrComputedState()._marks.values);
    final trailer = ByteData(4)..setUint32(0, marks.length);
    return (BytesBuilder(copy: false)
          ..add(fugue)
          ..add(marks)
          ..add(trailer.buffer.asUint8List()))
        .toBytes();
  }

  @override
  String toString() {
    final text = this.text;
    final cut = RuneOffsets.utf16Offset(text, 20);
    final truncated = cut < text.length ? '${text.substring(0, cut)}...' : text;
    return 'CRDTFugueRichText($id, "$truncated")';
  }
}

class RichTextState extends FugueState<String, List<RichTextSpan>> {
  RichTextState._(this._tree) : super(_tree, _unprojected);

  factory RichTextState.empty() => RichTextState._(FugueTree<String>.empty());

  final FugueTree<String> _tree;

  final Map<OperationId, _Mark> _marks = {};

  final Set<FugueElementID> _afterAnchored = {};

  final Set<String> _keys = {};

  _ResolvedMarks? _resolvedCache;

  List<RichTextSpan>? _spansCache;

  String? _textCache;

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
    for (final anchor in [mark.start, mark.end]) {
      if (anchor.side == _Anchor.after) {
        _afterAnchored.add(anchor.id!);
      }
    }
    _invalidateMarks();
  }

  void _treeChanged() {
    _textCache = null;
    _invalidateMarks();
  }

  void _invalidateMarks() {
    _resolvedCache = null;
    _spansCache = null;
  }

  _ResolvedMarks _resolved() =>
      _resolvedCache ??= _ResolvedMarks.resolve(_tree, _marks.values);

  String _text() => _textCache ??= _tree.values().join();

  List<RichTextSpan> _spans() {
    final cached = _spansCache;
    if (cached != null) {
      return cached;
    }
    final runes = _tree.values();
    final result = <RichTextSpan>[
      for (final run in _resolved().runs)
        RichTextSpan(runes.sublist(run.start, run.end).join(), run.attributes),
    ];
    return _spansCache = List.unmodifiable(result);
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

class _ResolvedRun {
  _ResolvedRun(this.start, this.end, this.attributes);

  final int start;
  int end;
  final Map<String, Object?> attributes;
}

class _ResolvedMarks {
  _ResolvedMarks(this.runs);

  factory _ResolvedMarks.resolve(
    FugueTree<String> tree,
    Iterable<_Mark> marks,
  ) {
    final length = tree.liveLength;
    final opens = <int, List<_Mark>>{};
    final closes = <int, List<_Mark>>{};
    for (final mark in marks) {
      final from = mark.start.liveStart(tree);
      final to = mark.end.liveEnd(tree, length);
      if (from == null || to == null || from >= to) {
        continue;
      }
      (opens[from] ??= []).add(mark);
      (closes[to] ??= []).add(mark);
    }

    final boundaries = SplayTreeSet<int>.of([0, length, ...opens.keys]);
    for (final at in closes.keys) {
      if (at < length) {
        boundaries.add(at);
      }
    }

    final active = <String, SplayTreeSet<_Mark>>{};
    final runs = <_ResolvedRun>[];
    final points = boundaries.toList();
    for (var i = 0; i + 1 < points.length; i++) {
      final at = points[i];
      for (final mark in closes[at] ?? const <_Mark>[]) {
        active[mark.key]?.remove(mark);
      }
      for (final mark in opens[at] ?? const <_Mark>[]) {
        (active[mark.key] ??= SplayTreeSet<_Mark>(_Mark.byStamp)).add(mark);
      }

      final attributes = <String, Object?>{};
      for (final entry in active.entries) {
        if (entry.value.isEmpty) {
          continue;
        }
        final winner = entry.value.last;
        if (winner.value != null) {
          attributes[entry.key] = winner.value;
        }
      }

      final next = points[i + 1];
      if (runs.isNotEmpty &&
          _sameAttributes(runs.last.attributes, attributes)) {
        runs.last.end = next;
      } else {
        runs.add(_ResolvedRun(at, next, Map.unmodifiable(attributes)));
      }
    }
    return _ResolvedMarks(runs);
  }

  final List<_ResolvedRun> runs;

  // The first run that ends after [index].
  int _runIndexAt(int index) {
    var low = 0;
    var high = runs.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (runs[middle].end <= index) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  Map<String, Object?> attributesAt(int index) {
    final at = _runIndexAt(index);
    return at < runs.length ? runs[at].attributes : const {};
  }

  List<({int start, int end, Map<String, Object?> attributes})> runsIn(
    int from,
    int to,
  ) {
    final result = <({int start, int end, Map<String, Object?> attributes})>[];
    for (var i = _runIndexAt(from); i < runs.length; i++) {
      final run = runs[i];
      if (run.start >= to) {
        break;
      }
      result.add(
        (
          start: run.start < from ? from : run.start,
          end: run.end > to ? to : run.end,
          attributes: run.attributes,
        ),
      );
    }
    return result;
  }

  List<({int end, Object? value})> keyRuns(String key, int from, int to) {
    final result = <({int end, Object? value})>[];
    for (final run in runsIn(from, to)) {
      final value = run.attributes[key];
      if (result.isNotEmpty && result.last.value == value) {
        result[result.length - 1] = (end: run.end, value: value);
      } else {
        result.add((end: run.end, value: value));
      }
    }
    return result;
  }

  bool isRedundant(int from, int to, String key, Object? value) {
    for (final run in runs) {
      if (run.end <= from || run.start >= to) {
        continue;
      }
      if (run.attributes[key] != value) {
        return false;
      }
    }
    return true;
  }

  static bool _sameAttributes(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
