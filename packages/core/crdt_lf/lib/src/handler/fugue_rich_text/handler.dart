// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_sequence_handler.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_snapshot.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_text_sequence_handler.dart';
import 'package:crdt_lf/src/snapshot/blob_version.dart';
import 'package:crdt_lf/src/utils/attributes.dart';
import 'package:crdt_lf/src/utils/binary_search.dart';
import 'package:crdt_lf/src/utils/embed_data.dart';

part 'anchor_slots.dart';
part 'delta_builder.dart';
part 'embed.dart';
part 'inversion.dart';
part 'mark.dart';
part 'mark_index.dart';
part 'operation.dart';
part 'resolved_marks.dart';
part 'state.dart';

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
/// `null`, `bool`, `int`, a finite `double` or `String`. [format] sets or
/// removes a key on a range, and [value] reads the text as [RichTextSpan]s.
/// Insert, delete and update work as in [CRDTFugueTextHandler]. The text can
/// also hold **embeds** (see below). See
/// [Rich text](https://mattiapispisa.it/crdt/docs/use-cases/rich-text).
///
/// Formats follow Peritext
/// ([Peritext: A CRDT for Collaborative Rich Text Editing](https://doi.org/10.1145/3555644)).
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
/// it, and neither does their removal. The same goes for a single embed.
///
/// ## Embeds
/// An embed is an object in the text, such as an image: one position, shown
/// in [text] as [RichTextSpan.objectReplacement] (U+FFFC). Its data is a map
/// written with [insertEmbed] and replaced with [updateEmbed]. [format],
/// [delete] and undo work on it as on a rune. Concurrent [updateEmbed]s of
/// one embed resolve like formats: the newest wins. An update loses against
/// a concurrent delete. The text never holds U+FFFC otherwise: [insert] and
/// [update] refuse it.
///
/// A block embed, such as a full-width image, is an embed followed by its own
/// `'\n'`, which holds the block attributes.
///
/// ## Snapshots
/// A snapshot keeps the tombstones, every mark and the data of the live
/// embeds, so ranges and expansion read the same after a restore. A mark
/// stays in the snapshot for good: the snapshot grows with each format. A
/// deleted embed leaves its data behind.
///
/// ## Deltas
/// [watch] emits a [RichTextDelta] per change. The text of an insert comes
/// with the attributes it has once the change is in. A format emits a retain
/// with attributes, only where the value moved. Embeds come as
/// [RichTextInsertEmbed] and [RichTextUpdateEmbed].
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
  CRDTFugueRichTextHandler(
    super.doc,
    super.id, {
    this.maxEmbedBytes = _defaultMaxEmbedBytes,
  }) : super(spec: CRDTFugueRichTextHandler.spec);

  // One change has to fit in the 1 MiB send buffer of crdt_socket_sync with
  // room to spare.
  static const int _defaultMaxEmbedBytes = 256 * 1024;

  /// The most encoded bytes the data of an embed written here can take;
  /// `null` for no limit. Defaults to 256 KiB.
  ///
  /// A local write policy: embeds from other peers are always read, whatever
  /// their size. Each byte stays in the change log until a snapshot and a
  /// prune and goes to every peer, so keep large media outside and store a
  /// reference, such as a URL.
  int? maxEmbedBytes;

  static const String _handlerType = 'CRDTFugueRichTextHandler';

  /// {@macro builtin_handler_spec}
  static const HandlerSpec<CRDTFugueRichTextHandler> spec = HandlerSpec(
    _handlerType,
    CRDTFugueRichTextHandler.new,
    formats: _formats,
  );

  static const int _kindMark = 4;
  static const int _kindEmbed = 5;
  static const int _kindEmbedUpdate = 6;

  static const HandlerFormats _formats = HandlerFormats(
    operationKinds: {
      OperationType.kindInsert,
      OperationType.kindDelete,
      OperationType.kindUpdate,
      _kindMark,
      _kindEmbed,
      _kindEmbedUpdate,
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

  late final OperationType _embedType = OperationType.custom(
    this,
    kind: _kindEmbed,
    name: 'embed',
  );

  late final OperationType _embedUpdateType = OperationType.custom(
    this,
    kind: _kindEmbedUpdate,
    name: 'embedUpdate',
    stamped: true,
  );

  @override
  late final OperationDecoders operationDecoders = {
    ...super.operationDecoders,
    _kindMark: (body) => _FugueRichTextMarkOperation.fromBodyBytes(this, body),
    _kindEmbed: (body) =>
        _FugueRichTextEmbedOperation.fromBodyBytes(this, body),
    _kindEmbedUpdate: (body) =>
        _FugueRichTextEmbedUpdateOperation.fromBodyBytes(this, body),
  };

  static void _refuseObjectReplacement(String text) {
    if (text.contains(RichTextSpan.objectReplacement)) {
      throw ArgumentError.value(
        text,
        'text',
        'holds U+FFFC, which stands for an embed',
      );
    }
  }

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
  /// Throws a [RangeError] for an [index] outside `0..length`, and an
  /// [ArgumentError] for a value [format] refuses or for a [text] that holds
  /// U+FFFC, before it writes. Use [insertEmbed] for an embed.
  @override
  void insert(
    int index,
    String text, {
    Map<String, Object?> attributes = const {},
    bool inherit = true,
  }) {
    RangeError.checkValueInInterval(index, 0, length, 'index');
    if (text.isEmpty) {
      return;
    }
    _refuseObjectReplacement(text);
    _insertWith(
      index,
      attributes,
      inherit: inherit,
      build: (leftOrigin, rightOrigin) => FugueTextInsertOperation.ofText(
        this,
        leftOrigin: leftOrigin,
        rightOrigin: rightOrigin,
        text: text,
      ),
    );
  }

  void _insertWith(
    int index,
    Map<String, Object?> attributes, {
    required bool inherit,
    required FugueTextInsertOperation Function(
      FugueElementID leftOrigin,
      FugueElementID rightOrigin,
    ) build,
  }) {
    for (final value in attributes.values) {
      _MarkValue.check(value);
    }

    final (leftOrigin, rightOrigin) = _insertOrigins(index);
    final insert = build(leftOrigin, rightOrigin);

    if (attributes.isEmpty && inherit) {
      doc.registerOperation(insert);
      return;
    }

    doc.runInTransaction(() {
      doc.registerOperation(insert);
      _markInserted(insert.items, attributes, inherit: inherit);
    });
  }

  /// Inserts an embed with the data [embed] at [index], **in runes**.
  ///
  /// The embed takes one position, shown as U+FFFC in [text]. [embed] maps
  /// `String` keys to `null`, `bool`, `int` (within ±(2^52 - 1)), a finite
  /// `double`, `String`, `Uint8List`, `List` or `Map` of these, nested at
  /// most 16 deep. The handler keeps an unmodifiable copy, in the key order
  /// given, where an integral `double` within that range is an `int`, as the
  /// other peers read it. Put the properties of the object, such as a URL or
  /// a width, in [embed], and the formats a user applies in [attributes].
  ///
  /// [attributes] cover the embed alone, like the block attributes of a
  /// `'\n'`: they never spread to text typed next to it. With [inherit], the
  /// embed also gets the formats around it that expand over it, as in
  /// [insert].
  ///
  /// Throws a [RangeError] for an [index] outside `0..length`, and an
  /// [ArgumentError] for data out of these rules or above [maxEmbedBytes] or
  /// for an attribute value [format] refuses, before it writes.
  ///
  /// ```dart
  /// text.insertEmbed(5, {'image': 'https://example.com/cat.png', 'w': 320});
  /// ```
  void insertEmbed(
    int index,
    Map<String, Object?> embed, {
    Map<String, Object?> attributes = const {},
    bool inherit = true,
  }) {
    RangeError.checkValueInInterval(index, 0, length, 'index');
    final prepared = _EmbedValue.prepare(embed, maxEmbedBytes);
    _insertWith(
      index,
      attributes,
      inherit: inherit,
      build: (leftOrigin, rightOrigin) => _FugueRichTextEmbedOperation(
        id: id,
        type: _embedType,
        leftOrigin: leftOrigin,
        rightOrigin: rightOrigin,
        element: FugueElementID(doc.peerId, nextCounter()),
        data: prepared.data,
        dataBytes: prepared.bytes,
      ),
    );
  }

  /// Throws the [ArgumentError] that [insertEmbed] throws for the data
  /// [embed], and writes nothing.
  void checkEmbed(Map<String, Object?> embed) {
    _EmbedValue.prepare(embed, maxEmbedBytes);
  }

  /// Throws the [ArgumentError] that [format] throws for [value], and writes
  /// nothing.
  void checkAttribute(Object? value) {
    _MarkValue.check(value);
  }

  /// Replaces the data of the embed at [index], **in runes**, with [embed].
  ///
  /// [embed] follows the rules of [insertEmbed]. The embed keeps its place
  /// and its attributes. Among concurrent updates of one embed the newest
  /// wins, as for formats. An update loses against a concurrent delete.
  ///
  /// Throws a [RangeError] for an [index] outside the text, and an
  /// [ArgumentError] when the rune at [index] is not an embed or the data is
  /// refused, before it writes.
  void updateEmbed(int index, Map<String, Object?> embed) {
    RangeError.checkValidIndex(index, this, 'index', length);
    final element = nodeAt(index);
    if (!cachedOrComputedState()._embeds.live.containsKey(element)) {
      throw ArgumentError.value(index, 'index', 'is not an embed');
    }
    final prepared = _EmbedValue.prepare(embed, maxEmbedBytes);
    doc.registerOperation(
      _FugueRichTextEmbedUpdateOperation(
        id: id,
        type: _embedUpdateType,
        element: element,
        data: prepared.data,
        dataBytes: prepared.bytes,
      ),
    );
  }

  /// Writes [text] over the runes from [index], **in runes**. A [text] that
  /// runs past the end is cut.
  ///
  /// Throws a [RangeError] for an [index] outside `0..length`, and an
  /// [ArgumentError] when [text] holds U+FFFC or the range covers an embed,
  /// before it writes. Use [updateEmbed] for an embed.
  @override
  void update(int index, String text) {
    RangeError.checkValueInInterval(index, 0, length, 'index');
    _refuseObjectReplacement(text);
    final embeds = cachedOrComputedState()._embeds.live;
    if (embeds.isNotEmpty) {
      final end = index + RuneOffsets.length(text);
      for (var i = index; i < end && i < length; i++) {
        if (embeds.containsKey(nodeAt(i))) {
          throw ArgumentError.value(index, 'index', 'covers an embed at $i');
        }
      }
    }
    super.update(index, text);
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
    var steps = 0;
    while (!node.isNull && !tree.isLive(node)) {
      if (++steps > state._walkLimit) {
        return _originsPastLongGap(state, index, left, right);
      }
      final next = nodeAfter(node);
      if (anchored.contains(node)) {
        origins = (node, next);
      }
      node = next;
    }
    return origins;
  }

  // The same rule over a long run of tombstones, as when typing where a big
  // block was deleted: walk only up to the last anchored one, found by its
  // live index, so typing there does not cost the length of the run.
  (FugueElementID, FugueElementID) _originsPastLongGap(
    RichTextState state,
    int index,
    FugueElementID left,
    FugueElementID right,
  ) {
    final tree = state._tree;
    // A tombstone of the run right after [left] has exactly [index] live
    // elements before it.
    final inGap = {
      for (final id in state._afterAnchored)
        if (!tree.isLive(id) && tree.liveIndexAfter(id) == index) id,
    };
    var origins = (left, right);
    var node = right;
    while (inGap.isNotEmpty) {
      final next = nodeAfter(node);
      if (inGap.remove(node)) {
        origins = (node, next);
      }
      node = next;
    }
    return origins;
  }

  // Inline runs expand after their end; a '\n' and an embed get block anchors,
  // so their attributes never spread to text typed next to them.
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
      final atBreak = i == items.length ||
          items[i].text == '\n' ||
          items[i].text == RichTextSpan.objectReplacement;
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
  /// edges as well, so text typed there stays without [key], except on a
  /// single `'\n'` or embed, where it keeps to that rune.
  ///
  /// An integral `double` within ±(2^52 - 1) is written as an `int`.
  ///
  /// Throws an [ArgumentError] when [value] is not `null`, `bool`, `int`, a
  /// finite `double` or `String`, or is an `int` outside ±(2^52 - 1).
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
    final state = cachedOrComputedState();
    final block = expand == MarkExpand.none &&
        to - from == 1 &&
        (state._tree.valueOf(first) == '\n' ||
            state._embeds.live.containsKey(first));
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

  @override
  RichTextState createEmptyState() => RichTextState.empty();

  // The marks the replay of [computeState] meets, kept for after the tree.
  List<_FugueRichTextMarkOperation>? _replayedMarks;

  // The embeds the replay of [computeState] meets.
  _EmbedTable? _replayedEmbeds;

  @override
  RichTextState computeState() {
    final snapshot = lastSnapshot();
    // The embeds of the snapshot come before the replay: an update replayed
    // after it must meet the stamp it competes with.
    final section = snapshot == null ? null : _MarksSection.read(snapshot);
    final replayed = _replayedMarks = [];
    final embeds = _replayedEmbeds = section?.embeds ?? _EmbedTable();
    final RichTextState state;
    try {
      state = super.computeState();
    } finally {
      _replayedMarks = null;
      _replayedEmbeds = null;
    }
    state._embeds = embeds;
    section?.marks.forEach(state._putMark);
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
    if (operation is _FugueRichTextEmbedUpdateOperation) {
      final won = state._embeds.update(operation);
      if (won) {
        state._spansCache = null;
      }
      sink?.add(
        won ? _embedUpdateDelta(state, operation) : const RichTextDelta.empty(),
      );
      return;
    }
    var applied = operation;
    // Only a hand-made remote update names an embed: this build refuses it.
    // Dropping those items keeps the data and the U+FFFC of the embed.
    if (operation is FugueTextUpdateOperation) {
      final kept = state._embeds.withoutEmbeds(operation);
      if (kept == null) {
        sink?.add(const RichTextDelta.empty());
        return;
      }
      applied = kept;
    }

    // The resolved runs shift with the text, so they need its delta.
    final shifts = state._resolvedCache != null &&
        (applied is FugueTextInsertOperation ||
            applied is FugueTextDeleteOperation);
    if (sink == null && !shifts) {
      super.applyOperation(state, applied);
      state._treeChanged(applied, null);
      return;
    }
    final collected = _SequenceCollector();
    super.applyOperation(state, applied, sink: collected);
    state._treeChanged(applied, collected.delta);
    sink?.add(_richDelta(state, applied, collected.delta));
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
    final embeds = _replayedEmbeds;
    if (embeds == null) {
      super.applyToTree(tree, operation, sink: sink);
      return;
    }
    switch (operation) {
      case final _FugueRichTextEmbedUpdateOperation update:
        embeds.update(update);
      case final FugueTextUpdateOperation update:
        final kept = embeds.withoutEmbeds(update);
        if (kept != null) {
          super.applyToTree(tree, kept, sink: sink);
        }
      case final _FugueRichTextEmbedOperation insert:
        super.applyToTree(tree, insert, sink: sink);
        embeds.inserted(insert);
      case final FugueTextDeleteOperation delete:
        super.applyToTree(tree, delete, sink: sink);
        embeds.deletedIn(delete);
      default:
        super.applyToTree(tree, operation, sink: sink);
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
    if (operation is _FugueRichTextEmbedUpdateOperation) {
      // Called before the update applies, so the table still holds the data
      // it replaces.
      final embed = cachedOrComputedState()._embeds.live[operation.element];
      return embed == null
          ? const []
          : [_embedUpdateOperation(operation.element, embed.data)];
    }
    final inverses = super.invert(operation);
    if (operation is FugueTextDeleteOperation && inverses.isNotEmpty) {
      return [...inverses, ..._restoreFormats(operation, inverses)];
    }
    return inverses;
  }

  // Cuts the run at each embed: the text between goes back as text, each
  // embed as an embed with its data. Each piece hangs off the last element
  // of the one before, as the elements of one insert do.
  @override
  List<({Operation insert, List<FugueElementID> was})> buildRestoreInserts({
    required FugueElementID leftOrigin,
    required FugueElementID rightOrigin,
    required List<({FugueElementID id, String value, FugueElementID was})>
        items,
  }) {
    final embeds = cachedOrComputedState()._embeds.live;
    if (embeds.isEmpty || !items.any((item) => embeds.containsKey(item.was))) {
      return super.buildRestoreInserts(
        leftOrigin: leftOrigin,
        rightOrigin: rightOrigin,
        items: items,
      );
    }

    final pieces = <({Operation insert, List<FugueElementID> was})>[];
    var left = leftOrigin;
    var start = 0;
    void addText(int end) {
      if (start == end) {
        return;
      }
      pieces.addAll(
        super.buildRestoreInserts(
          leftOrigin: left,
          rightOrigin: rightOrigin,
          items: items.sublist(start, end),
        ),
      );
      left = items[end - 1].id;
    }

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final embed = embeds[item.was];
      if (embed == null) {
        continue;
      }
      addText(i);
      pieces.add(
        (
          insert: _FugueRichTextEmbedOperation(
            id: id,
            type: _embedType,
            leftOrigin: left,
            rightOrigin: rightOrigin,
            element: item.id,
            data: embed.data,
          ),
          was: [item.was],
        ),
      );
      left = item.id;
      start = i + 1;
    }
    addText(items.length);
    return pieces;
  }

  _FugueRichTextEmbedUpdateOperation _embedUpdateOperation(
    FugueElementID element,
    Map<String, Object?> data,
  ) =>
      _FugueRichTextEmbedUpdateOperation(
        id: id,
        type: _embedUpdateType,
        element: element,
        data: data,
      );

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
    if (operation is _FugueRichTextEmbedUpdateOperation) {
      final latest = latestOf(operation.element);
      return latest == operation.element
          ? operation
          : _embedUpdateOperation(latest, operation.data);
    }
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
    final state = cachedOrComputedState();
    final marks = _MarksSection.write(state._marks.values, state._embeds);
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
