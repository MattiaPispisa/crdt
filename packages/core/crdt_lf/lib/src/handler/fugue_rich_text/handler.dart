// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:collection';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_sequence_handler.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_snapshot.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_text_sequence_handler.dart';
import 'package:crdt_lf/src/snapshot/blob_version.dart';
import 'package:crdt_lf/src/utils/attributes.dart';

part 'mark.dart';
part 'operation.dart';

/// Whether text typed at an edge of a formatted range gets the format too.
enum MarkExpand {
  /// Neither edge: text typed next to the range stays out, like a link.
  none,

  /// The start: text typed right before the range gets the format.
  before,

  /// The end: text typed right after the range gets the format, like bold.
  after,

  /// Both edges.
  both,
}

/// ## CRDT rich text with Fugue
///
/// ## Description
/// A Fugue text whose runes carry **attributes**: a key and a value, which is
/// `null`, `bool`, `int`, `double` or `String`. [format] sets or removes a
/// key on a range, and [value] reads the text as [RichTextSpan]s. Insert,
/// delete and update work as in [CRDTFugueTextHandler]. See the README
/// section "Rich text".
///
/// ## Convergence
/// A format is a mark anchored on the elements at the edges of its range.
/// On each rune, every key takes the value of the newest mark that covers
/// it: the highest HLC, then the highest peer id. So concurrent formats of
/// one key with the same HLC resolve by peer id. Text inserted inside a
/// range, even concurrently, is covered too.
///
/// ## Index space
/// One element is one **rune** (Unicode code point), in every index and
/// length. Use [RuneOffsets] to work with code units.
///
/// ## Expand modes
/// [MarkExpand] says if text typed later at an edge of a range gets the
/// format. Text typed where text was deleted follows the same rule, as if
/// the deleted text were still there.
///
/// ## Block attributes
/// A single `'\n'` formatted with [MarkExpand.none] holds the attributes of
/// its line, such as a header. They never spread to the text typed next to
/// it, and neither does their removal.
///
/// ## Snapshots
/// A snapshot keeps the tombstones and every mark, so ranges and expansion
/// read the same after a restore. A mark stays in the snapshot for good: the
/// snapshot grows with each format.
///
/// ## Deltas
/// [watch] emits a [RichTextDelta] per change. The text of an insert comes
/// with the attributes it has once the change is in. A format emits a retain
/// with attributes, only where the value moved.
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final text = CRDTFugueRichTextHandler(doc, 'note')
///   ..insert(0, 'Hello world\n')
///   ..format(0, 5, 'bold', true)
///   ..format(6, 5, 'link', 'https://example.com', expand: MarkExpand.none)
///   ..format(11, 1, 'header', 1, expand: MarkExpand.none);
/// print(text.text); // Prints "Hello world\n"
/// print(text.attributesAt(0)); // Prints "{bold: true}"
/// ```
base class CRDTFugueRichTextHandler
    extends FugueTextSequenceHandler<List<RichTextSpan>, RichTextState>
    with DeltaProvider<List<RichTextSpan>, RichTextDelta> {
  /// Opens the rich text handler `id` of `doc`.
  CRDTFugueRichTextHandler(super.doc, super.id)
      : super(spec: CRDTFugueRichTextHandler.spec);

  static const String _handlerType = 'CRDTFugueRichTextHandler';

  /// {@macro builtin_handler_spec}
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

  /// The operation type of a format.
  late final OperationType markType = OperationType.custom(
    this,
    kind: _kindMark,
    name: 'mark',
    stamped: true,
  );

  @override
  late final OperationDecoders operationDecoders = {
    ...super.operationDecoders,
    _kindMark: (body) => _FugueRichTextMarkOperation.fromBodyBytes(this, body),
  };

  /// Inserts [text] at [index], **in runes**, with [attributes] on top.
  ///
  /// With [inherit], [text] also gets the formats around it that expand over
  /// it. Without, it gets exactly [attributes]. A `null` value removes a key.
  /// Each `'\n'` of [text] gets [attributes] as block attributes; the other
  /// runs expand after their end, like [MarkExpand.after].
  ///
  /// The text and each key it changes are separate changes, written in one
  /// transaction. A key that changes nothing writes nothing.
  ///
  /// Throws an [ArgumentError] for a value [format] refuses, before it writes.
  @override
  void insert(
    int index,
    String text, {
    Map<String, Object?> attributes = const {},
    bool inherit = true,
  }) {
    if (text.isEmpty) {
      return;
    }
    for (final value in attributes.values) {
      _MarkValue.check(value);
    }

    final (leftOrigin, rightOrigin) = _insertOrigins(index);

    final insert = FugueTextInsertOperation.ofText(
      this,
      leftOrigin: leftOrigin,
      rightOrigin: rightOrigin,
      text: text,
    );

    if (attributes.isEmpty && inherit) {
      doc.registerOperation(insert);
      return;
    }

    doc.runInTransaction(() {
      doc.registerOperation(insert);
      _markInserted(insert.items, attributes, inherit: inherit);
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
    List<FugueTextInsertItem> items,
    Map<String, Object?> attributes, {
    required bool inherit,
  }) {
    final state = cachedOrComputedState();
    final resolved = state._resolved();
    final offset = state._tree.liveIndexAfter(items.first.id)! - 1;
    final marks = <Operation>[];

    void mark(int from, int to, _Anchor start, _Anchor end) {
      final keys = inherit
          ? attributes.keys
          : {
              ...attributes.keys,
              for (final run in resolved.runsIn(offset + from, offset + to))
                ...run.attributes.keys,
            };
      for (final key in keys) {
        final value = attributes[key];
        if (!resolved.isRedundant(offset + from, offset + to, key, value)) {
          marks.add(_markOperation(key, value, start, end));
        }
      }
    }

    var runStart = 0;
    for (var i = 0; i <= items.length; i++) {
      final atBreak = i == items.length || items[i].text == '\n';
      if (!atBreak) {
        continue;
      }
      if (runStart < i) {
        final next =
            i < items.length ? items[i].id : nodeAfter(items[i - 1].id);
        mark(
          runStart,
          i,
          _Anchor(_Anchor.before, items[runStart].id),
          next.isNull ? const _Anchor.text() : _Anchor(_Anchor.before, next),
        );
      }
      if (i < items.length) {
        final newline = items[i].id;
        mark(
          i,
          i + 1,
          _Anchor(_Anchor.before, newline),
          _Anchor(_Anchor.after, newline),
        );
      }
      runStart = i + 1;
    }
    marks.forEach(doc.registerOperation);
  }

  /// Sets [key] to [value] on the [length] runes from [index]; a `null`
  /// [value] removes [key].
  ///
  /// The range is clamped to the text. An empty range, or a format that
  /// changes nothing, writes nothing. [expand] says if text typed later at
  /// an edge gets [key] too. A removal with [MarkExpand.none] covers the
  /// edges as well, so text typed there stays without [key].
  ///
  /// Throws an [ArgumentError] when [value] is not `null`, `bool`, `int`,
  /// `double` or `String`, or is an `int` outside ±(2^52 - 1).
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

    // An unmark that kept to its range would leave text typed at its edges
    // under the old mark only.
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

  /// The attributes of the rune at [index]; unmodifiable.
  ///
  /// Throws a [RangeError] when [index] is outside the text.
  Map<String, Object?> attributesAt(int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    return cachedOrComputedState()._resolved().attributesAt(index);
  }

  /// The text as spans: runs of runes with the same attributes, in order.
  ///
  /// The list is unmodifiable, and the same object until the next change.
  /// {@macro fixed_value} Use [text] for the plain string.
  @override
  List<RichTextSpan> get value => cachedOrComputedState()._spans();

  /// The plain text, without attributes.
  String get text => cachedOrComputedState()._text();

  /// Changes the text to [newText] with the inserts and deletes [myersDiff]
  /// finds.
  ///
  /// The runes that stay keep their attributes. Inserted runes get the
  /// formats that expand over them, as with [insert].
  void change(String newText) => applyFugueTextChange(this, text, newText);

  @override
  RichTextState createEmptyState() => RichTextState.empty();

  // The marks the replay of [computeState] meets, kept for after the tree.
  List<_FugueRichTextMarkOperation>? _replayedMarks;

  @override
  RichTextState computeState() {
    final replayed = _replayedMarks = [];
    final RichTextState state;
    try {
      state = super.computeState();
    } finally {
      _replayedMarks = null;
    }
    final snapshot = lastSnapshot();
    if (snapshot != null) {
      _MarksSection.read(snapshot).forEach(state._putMark);
    }
    replayed.forEach(state._addMark);
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
      sink.add(_markDelta(state, operation));
      return;
    }

    // The resolved runs shift with the text, so they need its delta.
    final shifts = state._resolvedCache != null &&
        (operation is FugueTextInsertOperation ||
            operation is FugueTextDeleteOperation);
    if (sink == null && !shifts) {
      super.applyOperation(state, operation);
      state._treeChanged(operation, null);
      return;
    }
    final collected = _SequenceCollector();
    super.applyOperation(state, operation, sink: collected);
    state._treeChanged(operation, collected.delta);
    sink?.add(_richDelta(state, collected.delta));
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
  ) {
    final tree = state._tree;
    final from = operation.start.liveStart(tree);
    final to = operation.end.liveEnd(tree, tree.liveLength);
    if (from == null || to == null || from >= to) {
      state._addMark(operation);
      return const RichTextDelta.empty();
    }

    final key = operation.key;
    final was = state._resolved().keyRuns(key, from, to);
    if (!state._addMark(operation)) {
      return const RichTextDelta.empty();
    }
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
    // A mark resolves against the finished tree, so [computeState] folds the
    // marks after the replay, and [applyOperation] beside the tree.
    if (operation is _FugueRichTextMarkOperation) {
      _replayedMarks?.add(operation);
      return;
    }
    super.applyToTree(tree, operation, sink: sink);
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
    if (operation is FugueTextDeleteOperation && inverses.isNotEmpty) {
      return [...inverses, ..._restoreFormats(operation, inverses)];
    }
    return inverses;
  }

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

  // The Fugue part first, so the Fugue reader takes the blob as it is. The
  // length trailer finds the marks from the end.
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

  String _text() => _textCache ??= _tree.values().join();

  List<RichTextSpan> _spans() {
    final cached = _spansCache;
    if (cached != null) {
      return cached;
    }
    final runes = _tree.values();
    final result = <RichTextSpan>[
      for (final run in _resolved().runsIn(0, runes.length))
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

class _ResolvedRun {
  _ResolvedRun(this.start, this.end, this.winners, this.attributes);

  factory _ResolvedRun.of(int start, int end, Map<String, _Mark> winners) =>
      _ResolvedRun(
        start,
        end,
        winners,
        Map.unmodifiable({
          for (final entry in winners.entries)
            if (entry.value.value != null) entry.key: entry.value.value,
        }),
      );

  int start;
  int end;
  // The newest live mark of each key over the run, null values included.
  final Map<String, _Mark> winners;
  final Map<String, Object?> attributes;

  _ResolvedRun slice(int start, int end) =>
      _ResolvedRun(start, end, winners, attributes);

  bool sameWinners(_ResolvedRun other) {
    if (identical(winners, other.winners)) {
      return true;
    }
    if (winners.length != other.winners.length) {
      return false;
    }
    for (final entry in winners.entries) {
      if (!identical(other.winners[entry.key], entry.value)) {
        return false;
      }
    }
    return true;
  }
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

      final winners = <String, _Mark>{
        for (final entry in active.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value.last,
      };

      final run = _ResolvedRun.of(at, points[i + 1], winners);
      if (runs.isNotEmpty && runs.last.sameWinners(run)) {
        runs.last.end = run.end;
      } else {
        runs.add(run);
      }
    }
    return _ResolvedMarks(runs);
  }

  final List<_ResolvedRun> runs;

  // Puts [mark] over the live range [from, to): it wins where it is newer
  // than the current winner of its key.
  void patch(_Mark mark, int from, int to) {
    if (from >= to) {
      return;
    }
    final first = _runIndexAt(from);
    final last = _runIndexAt(to - 1);
    final low = first > 0 ? first - 1 : first;
    final high = last + 1 < runs.length ? last + 2 : last + 1;

    final region = <_ResolvedRun>[];
    void push(_ResolvedRun run) {
      if (region.isNotEmpty && region.last.sameWinners(run)) {
        region.last.end = run.end;
      } else {
        region.add(run);
      }
    }

    for (var i = low; i < high; i++) {
      final run = runs[i];
      if (run.end <= from || run.start >= to) {
        push(run.slice(run.start, run.end));
        continue;
      }
      if (run.start < from) {
        push(run.slice(run.start, from));
      }
      final start = run.start < from ? from : run.start;
      final end = run.end > to ? to : run.end;
      final current = run.winners[mark.key];
      if (current == null || _Mark.byStamp(current, mark) < 0) {
        push(_ResolvedRun.of(start, end, {...run.winners, mark.key: mark}));
      } else {
        push(run.slice(start, end));
      }
      if (run.end > to) {
        push(run.slice(to, run.end));
      }
    }
    runs.replaceRange(low, high, region);
  }

  int get length => runs.isEmpty ? 0 : runs.last.end;

  Map<String, _Mark> winnersAt(int index) => runs[_runIndexAt(index)].winners;

  void insert(int at, int count, Map<String, _Mark> winners) {
    var index = _runIndexAt(at);
    if (index < runs.length && runs[index].start < at) {
      final run = runs[index];
      runs.insert(index + 1, run.slice(at, run.end));
      run.end = at;
      index++;
    }
    for (var i = index; i < runs.length; i++) {
      runs[i]
        ..start += count
        ..end += count;
    }
    runs.insert(index, _ResolvedRun.of(at, at + count, winners));
    if (index + 1 < runs.length && runs[index].sameWinners(runs[index + 1])) {
      runs[index].end = runs.removeAt(index + 1).end;
    }
    if (index > 0 && runs[index - 1].sameWinners(runs[index])) {
      runs[index - 1].end = runs.removeAt(index).end;
    }
  }

  // Takes out the places a delete [delta] removes.
  void remove(SequenceDelta<String> delta) {
    final cuts = <(int, int)>[];
    var cursor = 0;
    for (final op in delta.ops) {
      if (op is SeqDelete<String>) {
        cuts.add((cursor, cursor + op.count));
        cursor += op.count;
      } else if (op is SeqRetain<String>) {
        cursor += op.count;
      }
    }

    var cut = 0;
    var removed = 0;
    int moved(int at) {
      while (cut < cuts.length && cuts[cut].$2 <= at) {
        removed += cuts[cut].$2 - cuts[cut].$1;
        cut++;
      }
      if (cut < cuts.length && cuts[cut].$1 < at) {
        return cuts[cut].$1 - removed;
      }
      return at - removed;
    }

    final low = _runIndexAt(cuts.first.$1);
    final reach = cuts.last.$2;
    var kept = low;
    for (var i = low; i < runs.length; i++) {
      final run = runs[i];
      final start = moved(run.start);
      final end = moved(run.end);
      if (start == end) {
        continue;
      }
      if (run.start <= reach && kept > 0 && runs[kept - 1].sameWinners(run)) {
        runs[kept - 1].end = end;
        continue;
      }
      runs[kept++] = run
        ..start = start
        ..end = end;
    }
    runs.length = kept;
  }

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
    var start = from;
    var end = from;
    Map<String, Object?>? attributes;
    for (var i = _runIndexAt(from); i < runs.length; i++) {
      final run = runs[i];
      if (run.start >= to) {
        break;
      }
      final runEnd = run.end > to ? to : run.end;
      if (attributes != null && sameAttributes(attributes, run.attributes)) {
        end = runEnd;
        continue;
      }
      if (attributes != null) {
        result.add((start: start, end: end, attributes: attributes));
      }
      start = run.start < from ? from : run.start;
      end = runEnd;
      attributes = run.attributes;
    }
    if (attributes != null) {
      result.add((start: start, end: end, attributes: attributes));
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
    for (var i = _runIndexAt(from); i < runs.length; i++) {
      final run = runs[i];
      if (run.start >= to) {
        break;
      }
      if (run.attributes[key] != value) {
        return false;
      }
    }
    return true;
  }
}
