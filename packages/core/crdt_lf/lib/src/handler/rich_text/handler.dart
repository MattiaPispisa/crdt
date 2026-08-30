import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_sequence_apply.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_sequence_handler.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_text_operations.dart';
import 'package:crdt_lf/src/handler/handler_type.dart';
import 'package:crdt_lf/src/snapshot/blob_version.dart';

part 'operation.dart';

/// # CRDT rich text, Peritext style
///
/// ## Description
/// Text with formatting that lives **outside** the characters. The text is a
/// Fugue sequence, one element per rune, exactly like `CRDTFugueTextHandler`.
/// The formatting is a set of [Mark]s whose ends are anchored to the identity
/// of a character rather than to its position.
///
/// That is what markup written *into* the text cannot do. Typed markers are
/// only characters: a collaborator can type between them, deleting one changes
/// the meaning of everything after it, and nothing ties a marker to the text it
/// was meant to cover. An anchored mark survives all of it, because the
/// character it hangs off keeps its identity while the text around it moves.
///
/// ## Algorithm
/// [Peritext](https://www.inkandswitch.com/peritext/). Marks are never
/// trimmed, split or removed: every [addMark] and [removeMark] is kept, and
/// the formatting of a character is the value of the highest-stamped mark of
/// that type covering it. The stamp is the id of the change that carried the
/// mark, so it costs no bytes of its own and orders the same way on every
/// peer.
///
/// Whether a mark grows when text is typed at its edge comes from the side its
/// anchors sit on — see [MarkAnchor]. `expand: true` (the default) is bold and
/// italic; `expand: false` is a link, which must not swallow what is typed
/// next to it.
///
/// ## Index space
/// One element is one **rune**. Use [RuneOffsets] to work with code units.
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final rich = CRDTRichTextHandler(doc, 'body');
/// rich
///   ..insert(0, 'Hello World')
///   ..addMark(start: 0, end: 5, type: 'bold', value: true);
/// print(rich.value.text);  // Hello World
/// print(rich.value.spans); // [MarkSpan(bold=true, 0..5)]
/// ```
base class CRDTRichTextHandler
    extends FugueSequenceHandler<String, RichTextValue, RichTextState>
    with DeltaProvider<RichTextValue, RichTextDelta> {
  /// Creates a rich text handler bound to [doc] with the given id.
  ///
  /// [valueCodec] encodes what a mark carries — `true` for bold, a URL for a
  /// link. The default is [JsonValueCodec], so any JSON value works.
  CRDTRichTextHandler(
    super.doc,
    super.id, {
    ValueCodec<Object?>? valueCodec,
  }) : valueCodec = valueCodec ?? const JsonValueCodec<Object?>();

  /// Stable type tag (minification-safe). See [Handler.handlerType].
  @override
  String get handlerType => kRichTextHandlerType;

  /// Turns what a mark carries into bytes and back.
  final ValueCodec<Object?> valueCodec;

  /// The kind that sets a mark.
  ///
  /// A fifth semantics next to insert, delete, update and move, so it declares
  /// its own kind. Stamped: the stamp is what picks the winner where two marks
  /// of one type cover the same character.
  late final OperationType markType = OperationType.custom(
    this,
    kind: _kMarkKind,
    name: 'mark',
    stamped: true,
  );

  /// The binary kind of [markType].
  static const int _kMarkKind = 4;

  /// The version of the snapshot blob this build writes and reads.
  static const int _snapshotVersion = 1;

  @override
  late final OperationDecoders operationDecoders = {
    OperationType.kindInsert: (body) =>
        FugueTextInsertOperation.fromBodyBytes(this, body),
    OperationType.kindDelete: (body) =>
        FugueTextDeleteOperation.fromBodyBytes(this, body),
    OperationType.kindUpdate: (body) =>
        FugueTextUpdateOperation.fromBodyBytes(this, body),
    _kMarkKind: (body) => _RichTextMarkOperation.fromBodyBytes(this, body),
  };

  // --- Text ---------------------------------------------------------------

  /// The characters, with no formatting markers among them.
  ///
  /// Cheaper than `value.text`: it skips resolving the marks.
  String get text => RichTextState.textOf(treeOf(cachedOrComputedState()));

  /// The formatting covering [text], sorted and non-overlapping per type.
  List<MarkSpan> get spans => value.spans;

  /// The length of [text], **in runes**.
  int get length => elementCount;

  /// Inserts [text] at [index], **in runes**.
  ///
  /// A mark whose edge sits at [index] grows over the new text when it was
  /// added with `expand: true`, and keeps its size otherwise.
  void insert(int index, String text) {
    if (text.isEmpty) {
      return;
    }

    final leftOrigin = originBefore(index);
    final rightOrigin = nodeAfter(leftOrigin);

    final items = <FugueTextInsertItem>[];
    for (final rune in text.runes) {
      items.add(
        FugueTextInsertItem(
          id: FugueElementID(doc.peerId, nextCounter()),
          text: String.fromCharCode(rune),
        ),
      );
    }

    doc.registerOperation(
      FugueTextInsertOperation.fromHandler(
        this,
        leftOrigin: leftOrigin,
        rightOrigin: rightOrigin,
        items: items,
      ),
    );
  }

  /// Overwrites the runes starting at [index] with [text], keeping the
  /// identity of each one — so the marks anchored to them stay put.
  ///
  /// Stops at the end of the text instead of inserting. An update loses
  /// against a concurrent deletion of the same element.
  void update(int index, String text) {
    if (text.isEmpty) {
      return;
    }

    final runes = text.runes.toList();
    final items = <FugueTextUpdateItem>[];
    for (var i = 0; i < runes.length; i += 1) {
      final nodeID = nodeAt(index + i);
      if (nodeID.isNull) {
        break;
      }
      items.add(
        FugueTextUpdateItem(
          nodeID: nodeID,
          text: String.fromCharCode(runes[i]),
        ),
      );
    }

    if (items.isEmpty) {
      return;
    }

    doc.registerOperation(
      FugueTextUpdateOperation.fromHandler(this, items: items),
    );
  }

  /// Changes the whole text to [newText] with the
  /// [Myers diff algorithm](http://www.xmailserver.org/diff2.pdf), keeping the
  /// characters the two texts share — and with them their formatting.
  ///
  /// It emits several operations, so run it inside
  /// [CRDTDocument.runInTransaction].
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

  // --- Marks --------------------------------------------------------------

  /// Sets [type] to [value] over the runes `[start, end)`.
  ///
  /// With [expand] on, text typed at either edge takes the mark too, which is
  /// what bold and italic do. Turn it off for a link, so typing next to one
  /// does not extend it.
  ///
  /// A range that is empty or backwards does nothing.
  void addMark({
    required int start,
    required int end,
    required String type,
    required Object value,
    bool expand = true,
  }) {
    _mark(start: start, end: end, type: type, value: value, expand: expand);
  }

  /// Takes [type] off the runes `[start, end)`.
  ///
  /// Nothing is trimmed or deleted: the removal is a mark of its own that
  /// wins over what came before it. Marks outside the range keep their value,
  /// and a mark that only partly overlaps keeps the part that is left.
  ///
  /// [expand] must match how the mark was added, or text typed at the edge
  /// takes the old value back.
  void removeMark({
    required int start,
    required int end,
    required String type,
    bool expand = true,
  }) {
    _mark(start: start, end: end, type: type, value: null, expand: expand);
  }

  void _mark({
    required int start,
    required int end,
    required String type,
    required Object? value,
    required bool expand,
  }) {
    if (end <= start) {
      return;
    }
    final mark = Mark(
      start: anchorAt(start, expand ? MarkSide.after : MarkSide.before),
      end: anchorAt(end, expand ? MarkSide.before : MarkSide.after),
      type: type,
      value: value,
    );
    doc.registerOperation(
      _RichTextMarkOperation.fromHandler(this, mark: mark),
    );
  }

  /// The anchor for the boundary at [index], hanging off [side] of a
  /// character.
  ///
  /// [MarkSide.after] takes the character before the boundary,
  /// [MarkSide.before] the one after it. A boundary with no such character —
  /// the start or the end of the text — anchors to the document edge instead.
  ///
  /// The inverse of [indexOfAnchor]. `O(√n)`.
  MarkAnchor anchorAt(int index, MarkSide side) {
    if (side == MarkSide.after) {
      if (index <= 0) {
        return MarkAnchor.documentStart();
      }
      final id = nodeAt(index - 1);
      return id.isNull ? MarkAnchor.documentEnd() : MarkAnchor(id, side);
    }
    final id = nodeAt(index);
    return id.isNull ? MarkAnchor.documentEnd() : MarkAnchor(id, side);
  }

  /// The rune offset [anchor] currently stands for, or `null` when it names a
  /// character this document has not seen yet.
  ///
  /// An anchor on a deleted character resolves to where that character used to
  /// be, so re-typing there brings the mark back. `O(√n)`.
  int? indexOfAnchor(MarkAnchor anchor) =>
      _resolveAnchor(anchor, treeOf(cachedOrComputedState()));

  static int? _resolveAnchor(MarkAnchor anchor, FugueTree<String> tree) {
    if (anchor.id.isNull) {
      return anchor.side == MarkSide.before ? 0 : tree.liveLength;
    }
    final after = tree.liveIndexAfter(anchor.id);
    if (after == null) {
      return null;
    }
    return anchor.side == MarkSide.after ? after : after - 1;
  }

  static List<MarkSpan> _spansOf(
    FugueTree<String> tree,
    Map<OperationId, Mark> marks,
  ) {
    if (marks.isEmpty) {
      return const [];
    }
    return resolveMarkSpans(
      marks: marks,
      length: tree.liveLength,
      resolveAnchor: (anchor) => _resolveAnchor(anchor, tree),
    );
  }

  // --- Framework ----------------------------------------------------------

  /// The text together with the formatting that covers it.
  ///
  /// Reading is also how the delta stream is told what the caller now knows:
  /// a consumer seeds from a read, so the next delta only has to carry the
  /// formatting when it has moved away from this point.
  @override
  RichTextValue get value {
    final state = cachedOrComputedState();
    final resolved = super.value;
    state.lastSpans = resolved.spans;
    return resolved;
  }

  @override
  RichTextState createEmptyState() => RichTextState.empty();

  @override
  void applyToTree(
    FugueTree<String> tree,
    Operation operation, {
    DeltaSink<Object?>? sink,
  }) {
    // Never reached: [applyToState] is what this handler routes through, and
    // it needs the marks as well as the tree.
    throw UnsupportedError(
      'CRDTRichTextHandler applies operations through applyToState',
    );
  }

  @override
  void applyToState(
    RichTextState state,
    Operation operation, {
    DeltaSink<Object?>? sink,
  }) {
    final tree = treeOf(state);
    var text = const SequenceDelta<String>.empty();

    if (operation is _RichTextMarkOperation) {
      // The stamp is minted before the operation gets here, and it is what the
      // mark is keyed by: two peers marking at once keep both entries.
      state.marks[operation.stamp!] = operation.mark;
    } else if (sink == null) {
      applyFugueSequenceOperation<String>(tree, operation);
    } else {
      final capture = _SequenceCapture();
      applyFugueSequenceOperation<String>(tree, operation, sink: capture);
      text = capture.delta;
    }

    if (sink == null) {
      // Nobody is watching, so the formatting is not worked out. What was
      // last reported no longer stands for anything: forget it, and let the
      // next delta carry the spans in full.
      state.lastSpans = null;
      return;
    }

    // Worked out from the tree and the marks, never from the projected text,
    // so watching costs the formatting rather than a read of the document.
    final spans = _spansOf(tree, state.marks);
    final moved = !_sameSpans(spans, state.lastSpans);
    state.lastSpans = spans;
    sink.add(RichTextDelta(text: text, spans: moved ? spans : null));
  }

  static bool _sameSpans(List<MarkSpan> a, List<MarkSpan>? b) {
    if (b == null || a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  Iterable<FugueElementID> producedElementIds(Operation operation) sync* {
    if (operation is FugueTextInsertOperation) {
      for (final item in operation.items) {
        yield item.id;
      }
    }
  }

  @override
  Operation buildDeleteOperation(List<FugueElementID> nodeIDs) {
    return FugueTextDeleteOperation.fromHandler(
      this,
      items: nodeIDs.map((id) => FugueTextDeleteItem(nodeID: id)).toList(),
    );
  }

  @override
  Uint8List encodeRun(List<String> values) => Wtf8.encodeAll(values);

  @override
  List<String> decodeRun(Uint8List blob, int length) =>
      Wtf8.decodeCodePoints(blob);

  @override
  RichTextValue applyDelta(RichTextValue base, RichTextDelta delta) =>
      delta.apply(base);

  // --- Snapshot -----------------------------------------------------------

  /// The snapshot blob: the marks, then the sequence.
  ///
  /// Layout:
  /// - `version: u8`
  /// - `marksLen: uvarint`
  /// - `marks: bytes` — see [_encodeMarks]
  /// - `sequence: bytes` — the Fugue blob, read back through [fugueSectionOf]
  ///
  /// The marks go first so the sequence keeps a section of its own, which the
  /// inherited decoder can read without knowing anything about them.
  @override
  Uint8List getSnapshotState() {
    final out = BytesBuilder(copy: false)..addByte(_snapshotVersion);
    UVarint.writeBytes(
      _encodeMarks(cachedOrComputedState().marks),
      out,
    );
    return (out..add(super.getSnapshotState())).toBytes();
  }

  @override
  Uint8List fugueSectionOf(Uint8List snapshot) {
    return Uint8List.sublistView(snapshot, _marksSection(snapshot).nextOffset);
  }

  @override
  void seedState(RichTextState state) {
    final snapshot = lastSnapshot();
    if (snapshot == null) {
      return;
    }
    state.marks.addAll(_decodeMarks(_marksSection(snapshot).value));
  }

  ({Uint8List value, int nextOffset}) _marksSection(Uint8List snapshot) {
    final offset = SnapshotBlob.read(
      snapshot,
      version: _snapshotVersion,
      name: 'rich text',
    );
    return UVarint.readBytes(
      snapshot,
      offset: offset,
      what: 'rich text marks',
    );
  }

  /// Encodes the marks table.
  ///
  /// Layout: `count: uvarint`, then per mark `stamp:`
  /// [OperationId.byteLength] bytes followed by the body
  /// [_RichTextMarkOperation] writes.
  Uint8List _encodeMarks(Map<OperationId, Mark> marks) {
    final out = BytesBuilder(copy: false);
    UVarint.write(marks.length, out);
    for (final entry in marks.entries) {
      out
        ..add(entry.key.toUint8List())
        ..add(
          _RichTextMarkOperation(
            id: id,
            type: markType,
            valueCodec: valueCodec,
            mark: entry.value,
          ).toBodyBytes(),
        );
    }
    return out.toBytes();
  }

  Map<OperationId, Mark> _decodeMarks(Uint8List bytes) {
    final marks = <OperationId, Mark>{};
    final countRec = UVarint.read(bytes, offset: 0);
    var offset = countRec.nextOffset;

    for (var i = 0; i < countRec.value; i += 1) {
      final stamp = OperationId.readFromBytes(bytes, offset: offset);
      offset += OperationId.byteLength;

      final startRec = MarkAnchor.readFromBytes(bytes, offset: offset);
      offset = startRec.nextOffset;
      final endRec = MarkAnchor.readFromBytes(bytes, offset: offset);
      offset = endRec.nextOffset;

      final typeRec = UVarint.readBytes(
        bytes,
        offset: offset,
        what: 'rich text mark type',
      );
      offset = typeRec.nextOffset;

      if (offset >= bytes.length) {
        throw const FormatException('Truncated rich text mark');
      }
      final hasValue = bytes[offset];
      offset += 1;
      if (hasValue > 1) {
        throw FormatException('Invalid rich text mark value flag: $hasValue');
      }

      Object? value;
      if (hasValue == 1) {
        final valueRec = UVarint.readBytes(
          bytes,
          offset: offset,
          what: 'rich text mark value',
        );
        value = valueCodec.decode(valueRec.value);
        offset = valueRec.nextOffset;
      }

      marks[stamp] = Mark(
        start: startRec.value,
        end: endRec.value,
        type: utf8.decode(typeRec.value),
        value: value,
      );
    }
    return marks;
  }

  @override
  String toString() {
    final shown = text;
    final cut = RuneOffsets.utf16Offset(shown, 20);
    final truncated =
        cut < shown.length ? '${shown.substring(0, cut)}...' : shown;
    return 'CRDTRichText($id, "$truncated", ${spans.length} spans)';
  }
}

/// Collects the [SequenceDelta] the shared Fugue apply reports, so it can be
/// wrapped into the [RichTextDelta] this handler publishes.
class _SequenceCapture implements DeltaSink<Object?> {
  SequenceDelta<String> delta = const SequenceDelta<String>.empty();

  @override
  void add(Object? value) {
    if (value is SequenceDelta<String>) {
      delta = value;
    }
  }
}

/// State of the [CRDTRichTextHandler]: the sequence, plus the marks that cover
/// it.
class RichTextState extends FugueState<String, RichTextValue> {
  // The marks are taken as a parameter rather than read off `this`, because a
  // super-initializer cannot reach the instance being built.
  RichTextState._(FugueTree<String> tree, this.marks)
      : super(tree, (t) => _project(t, marks));

  /// Creates an empty state.
  factory RichTextState.empty() =>
      RichTextState._(FugueTree<String>.empty(), <OperationId, Mark>{});

  /// Every mark ever written, keyed by the stamp that orders them.
  final Map<OperationId, Mark> marks;

  /// The spans last reported on the delta stream, so an operation that leaves
  /// the formatting alone can say so instead of resending it.
  List<MarkSpan>? lastSpans;

  /// The characters [tree] holds, in order.
  static String textOf(FugueTree<String> tree) => tree.values().join();

  static RichTextValue _project(
    FugueTree<String> tree,
    Map<OperationId, Mark> marks,
  ) {
    return RichTextValue(
      text: textOf(tree),
      spans: CRDTRichTextHandler._spansOf(tree, marks),
    );
  }
}
