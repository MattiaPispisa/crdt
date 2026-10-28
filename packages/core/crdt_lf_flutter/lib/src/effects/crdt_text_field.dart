// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/common/_crdt_guards.dart';
import 'package:crdt_lf_flutter/src/editor/crdt_editor_binding.dart';
import 'package:crdt_lf_flutter/src/effects/text_delta.dart';
import 'package:crdt_lf_flutter/src/provider/_crdt_view.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_helper.dart';
import 'package:flutter/widgets.dart';

/// Whether [CrdtTextFieldBuilder] compares its whole text against the handler.
///
/// The field derives its text from the deltas instead of projecting the whole
/// document, and checks the result after every step — in release too, with a
/// question that costs nothing: the whole string for `CRDTTextHandler`, the
/// O(1) length for `CRDTFugueTextHandler`. A drift that keeps the length is the
/// one that cheap question cannot see.
///
/// While `true`, a debug build **also** compares the whole value and throws on
/// a mismatch, closing that gap. That comparison reads the value, which is the
/// cost the field exists to avoid, so only a benchmark should turn it off.
bool debugVerifyCrdtTextFieldProjection = true;

/// {@template crdt_text_field_builder}
/// Binds a [TextEditingController] to the text handler registered under [id]
/// (`CRDTTextHandler` or `CRDTFugueTextHandler`):
///
/// - **Local edits** are pushed into the handler immediately, as the precise
///   [TextDelta] of each editing gesture (common prefix/suffix trimming — no
///   full-text diff, no debounce). Multi-op gestures run in a single
///   transaction, so each gesture emits one document update.
/// - **IME composition** is respected: while a composing region is active
///   (CJK input, autocorrect) nothing is committed; the accumulated delta is
///   pushed when composition ends.
/// - **Remote changes** are adopted into the controller in place, with the
///   caret and selection kept visually anchored. With a
///   `CRDTFugueTextHandler` the anchor is a stable position
///   ([CRDTFugueTextHandler.stablePositionAt]) tied to the identity of the
///   element left of the caret. Without one, the offsets ride on the
///   `SequenceDelta` the handler reports, which says exactly what moved even
///   when a change touched several regions. Only a change no delta can
///   describe — a snapshot import, a dropped cache — falls back to a diff of
///   the two texts.
/// - The subtree **never rebuilds**: the widget listens to the document
///   directly and updates the controller, exactly like a headless editor
///   binding. [builder] runs once.
///
/// ## Example
/// ```dart
/// CrdtTextFieldBuilder(
///   id: 'note',
///   builder: (context, controller) => TextField(controller: controller),
/// ),
/// ```
/// {@endtemplate}
class CrdtTextFieldBuilder extends StatefulWidget {
  /// Create a CrdtTextFieldBuilder.
  ///
  /// {@macro crdt_text_field_builder}
  const CrdtTextFieldBuilder({
    required this.id,
    required this.builder,
    this.onSelectionAnchorsChanged,
    this.deletedBuilder,
    super.key,
  });

  /// The id of the text handler to bind (as registered on the document).
  final String id;

  /// Called once with the [TextEditingController] internally handled.
  final Widget Function(
    BuildContext context,
    TextEditingController textEditingController,
  ) builder;

  /// Called whenever the stable anchors of the local selection change
  /// ([CRDTFugueTextHandler.stablePositionAt] of the selection base and
  /// extent) — ready to be published as ephemeral presence (e.g. the
  /// awareness plugin of `crdt_socket_sync`), so that other peers can draw
  /// this user's cursor with `CrdtTextCursorsOverlay`.
  ///
  /// Anchors are only reported **while the field has focus** — a user has
  /// one text cursor, where they are typing. When focus leaves the field
  /// (Flutter keeps the controller's selection on blur) the callback fires
  /// once with `null`s so the published cursor is withdrawn.
  ///
  /// `null` anchors mean "no anchored selection right now": the field is
  /// not focused, has no valid selection, an IME composition is pending, or
  /// the handler is not Fugue-based (only Fugue handlers carry element
  /// identity).
  final void Function(FugueElementID? base, FugueElementID? extent)?
      onSelectionAnchorsChanged;

  /// {@macro crdt_deleted_builder}
  ///
  /// The published anchors are withdrawn with `null`s.
  final WidgetBuilder? deletedBuilder;

  @override
  State<CrdtTextFieldBuilder> createState() => _CrdtTextFieldBuilderState();
}

class _CrdtTextFieldBuilderState extends State<CrdtTextFieldBuilder> {
  TextEditingController? _controller;

  /// Set by the first `build`; everything else runs after one.
  late CRDTDocument _document;

  /// The handler's delta stream, and the guard around a push (see
  /// [CrdtEditorBinding.push]).
  late final CrdtEditorBinding<String, SequenceDelta<String>> _binding =
      CrdtEditorBinding<String, SequenceDelta<String>>(
    // Not the generic resolver: this widget accepts two named handlers and
    // says so, which is a better error than "the wrong delta shape".
    resolve: _deltaProviderOf,
    onReset: (value, cause) {
      if (_seeding) {
        _seed(value);
        return;
      }
      _settle(text: value);
    },
    onRemoteDelta: (event) => _settle(reported: event.delta),
    verifyProjection: _projectionAgrees,
    // An empty Fugue delta still has to commit a pending composition.
    skipEmptyDeltas: false,
  );

  /// Whether [_binding] is reading the value while attaching.
  ///
  /// That read builds the controller the first time, so it skips [_settle].
  bool _seeding = false;

  /// The handler-side text this widget has last pushed or adopted. Local
  /// deltas are computed against it.
  String _lastCommittedText = '';

  /// How many runes [_lastCommittedText] holds.
  ///
  /// Carried by arithmetic — every delta says how many elements it puts in and
  /// takes out — so [_projectionAgrees] can ask the handler whether the two
  /// still agree without counting anything.
  int _lastCommittedRunes = 0;

  /// Stable anchors ([CRDTFugueTextHandler.stablePositionAt]) for the current
  /// selection, captured whenever controller and handler agree. `null` while
  /// they diverge (a composition is pending) or for a non-Fugue handler —
  /// [_adopt] then places the offsets from the reported delta instead.
  FugueElementID? _selectionBaseAnchor;
  FugueElementID? _selectionExtentAnchor;

  /// Whether the field inside [CrdtTextFieldBuilder.builder] has focus.
  /// Anchors keep being captured regardless (they anchor [_adopt] too), but
  /// they are only *published* while focused: an unfocused field retains
  /// its selection, which is not the collaborator's cursor.
  bool _hasFocus = false;

  /// What was last handed to [CrdtTextFieldBuilder.onSelectionAnchorsChanged].
  FugueElementID? _publishedBase;
  FugueElementID? _publishedExtent;

  @override
  Widget build(BuildContext context) {
    final document = _document = context.liveDocument('CrdtTextFieldBuilder');
    // Rebuilds only when this flips, so the field still builds once.
    if (context.selectCrdtDocument((doc) => doc.isDeleted(widget.id))) {
      _binding.detach();
      // Not here: the callback is the user's, and this is a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _invalidateSelectionAnchors();
        }
      });
      return buildDeleted(context, widget.deletedBuilder);
    }
    // Covers a new document and a new id alike, which is why there is no
    // `didUpdateWidget`: `build` always runs after one.
    _seeding = true;
    try {
      _binding.attach(
        document,
        widget.id,
        // The anchors belong to the old handler; they must go before anything
        // reads the new one, because seeding captures them again.
        onBeforeAttach: _invalidateSelectionAnchors,
      );
    } finally {
      _seeding = false;
    }
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: _onFocusChange,
      child: widget.builder(context, _controller!),
    );
  }

  @override
  void dispose() {
    _binding.dispose();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  /// Takes in the text read while attaching, building the controller the
  /// first time and adopting into it afterwards.
  void _seed(String seeded) {
    if (_controller == null) {
      _lastCommittedText = seeded;
      _lastCommittedRunes = RuneOffsets.length(seeded);
      _controller = TextEditingController(text: seeded);
      _controller!.addListener(_onControllerChanged);
      return;
    }
    _adopt(seeded, runes: RuneOffsets.length(seeded));
  }

  DeltaProvider<String, SequenceDelta<String>> _deltaProviderOf(
    BaseCRDTDocument document,
    String id,
  ) {
    // Both text handlers publish this shape; [_handlerOf] refuses anything
    // else.
    return _handlerOf(document, id)
        as DeltaProvider<String, SequenceDelta<String>>;
  }

  Handler<dynamic> _handler() => _handlerOf(_document, widget.id);

  Handler<dynamic> _handlerOf(BaseCRDTDocument document, String id) {
    final handler = document.handlerById(id);
    if (handler is CRDTTextHandler || handler is CRDTFugueTextHandler) {
      return handler!;
    }
    throw FlutterError(
      'CrdtTextFieldBuilder expected a CRDTTextHandler or '
      'CRDTFugueTextHandler registered under id "$id", '
      'but found ${handler ?? 'none'}.',
    );
  }

  /// Pushes [delta] into the handler. Its offsets are code-unit offsets into
  /// [against], the handler's text as the delta was computed against it.
  ///
  /// Returns how many runes the push takes out and puts in, which is what
  /// keeps [_lastCommittedRunes] right without counting the text again.
  ({int deleted, int inserted}) _applyDelta(TextDelta delta, String against) {
    final handler = _handler();

    // [TextDelta] is expressed in code units, the handlers in runes. The
    // delta's boundaries are snapped to code-point boundaries by
    // [computeTextDelta], so both ends convert exactly.
    final index = RuneOffsets.runeIndex(against, delta.index);
    final deleted = delta.deleted == 0
        ? 0
        : RuneOffsets.runeIndex(against, delta.index + delta.deleted) - index;
    final inserted = RuneOffsets.length(delta.inserted);

    // One body for both handlers: same `insert` and `delete`, no shared type.
    void run() {
      if (deleted > 0) {
        if (handler is CRDTTextHandler) {
          handler.delete(index, deleted);
        } else {
          (handler as CRDTFugueTextHandler).delete(index, deleted);
        }
      }
      if (delta.inserted.isNotEmpty) {
        if (handler is CRDTTextHandler) {
          handler.insert(index, delta.inserted);
        } else {
          (handler as CRDTFugueTextHandler).insert(index, delta.inserted);
        }
      }
    }

    _document.runInTransaction(run);
    return (deleted: deleted, inserted: inserted);
  }

  /// Captures the stable anchors of the current selection.
  ///
  /// Only meaningful when the controller text matches the handler text (the
  /// offsets must be valid in the handler's coordinates).
  void _captureSelectionAnchors() {
    final handler = _document.handlerById(widget.id);
    if (handler is! CRDTFugueTextHandler) {
      return;
    }
    final selection = _controller!.selection;
    // Selection offsets are code-unit offsets; the handler anchors by rune.
    final text = _controller!.text;
    _setSelectionAnchors(
      selection.baseOffset < 0
          ? null
          : handler.stablePositionAt(
              RuneOffsets.runeIndex(text, selection.baseOffset),
            ),
      selection.extentOffset < 0
          ? null
          : handler.stablePositionAt(
              RuneOffsets.runeIndex(text, selection.extentOffset),
            ),
    );
  }

  void _invalidateSelectionAnchors() {
    _setSelectionAnchors(null, null);
  }

  void _setSelectionAnchors(FugueElementID? base, FugueElementID? extent) {
    if (base == _selectionBaseAnchor && extent == _selectionExtentAnchor) {
      return;
    }
    _selectionBaseAnchor = base;
    _selectionExtentAnchor = extent;
    _publishAnchors();
  }

  void _onFocusChange(bool hasFocus) {
    if (_hasFocus == hasFocus) {
      return;
    }
    _hasFocus = hasFocus;
    _publishAnchors();
  }

  void _publishAnchors() {
    final base = _hasFocus ? _selectionBaseAnchor : null;
    final extent = _hasFocus ? _selectionExtentAnchor : null;
    if (base == _publishedBase && extent == _publishedExtent) {
      return;
    }
    _publishedBase = base;
    _publishedExtent = extent;
    widget.onSelectionAnchorsChanged?.call(base, extent);
  }

  /// Local edits: push the delta of the gesture into the handler.
  void _onControllerChanged() {
    if (_document.isDeleted(widget.id)) {
      // Until the next frame swaps the field out, an edit has nowhere to go.
      return;
    }
    final value = _controller!.value;
    if (value.text == _lastCommittedText) {
      // Selection-only change, or a canceled composition.
      _captureSelectionAnchors();
      return;
    }
    if (value.isComposingRangeValid) {
      // Mid-composition (IME/autocorrect): commit when composition ends. The
      // anchors go stale with the uncommitted text.
      _invalidateSelectionAnchors();
      return;
    }
    _pushLocalEdits();
  }

  /// Pushes the gesture the controller is holding into the handler.
  ///
  /// [handlerState] is what the handler holds now, when the caller knows it. It
  /// is believed only while the stream is level: it describes **one** event,
  /// and a burst is published at once but delivered one at a time, so the
  /// handler has already folded the rest. When the stream is ahead, one read
  /// settles it instead — guessing pushes the edit at the wrong index and marks
  /// the events still in flight as accounted for, dropping them.
  void _pushLocalEdits({({String text, int runes})? handlerState}) {
    var known = handlerState;
    if (_binding.isBehind) {
      final value = _binding.readSynced();
      known = (text: value, runes: RuneOffsets.length(value));
    }
    final handlerText = known?.text ?? _lastCommittedText;
    final handlerRunes = known?.runes ?? _lastCommittedRunes;

    final target = _controller!.text;

    // The post-edit caret disambiguates edits inside a run of identical
    // characters (e.g. a newline typed right before another newline), so the
    // gesture is recorded where the user actually is, not slid past it.
    final selection = _controller!.selection;
    final caret = selection.isCollapsed ? selection.baseOffset : null;
    final delta = computeTextDelta(_lastCommittedText, target, caret: caret);
    if (delta == null) {
      // Nothing of ours to push — both callers rule this out, but whatever the
      // handler moved still has to be taken in rather than dropped.
      if (known != null) {
        _adopt(handlerText, runes: handlerRunes);
      }
      return;
    }

    var pushed = delta;
    if (handlerText != _lastCommittedText) {
      // Rare: a remote change landed while local edits were pending (only
      // possible during composition). Rebase the local delta onto the merged
      // text, best-effort, and let the CRDT do the merging.
      final remote = computeTextDelta(_lastCommittedText, handlerText)!;
      final index = mapOffsetThroughDelta(delta.index, remote)
          .clamp(0, handlerText.length);
      final deletable = handlerText.length - index;
      pushed = TextDelta(
        index: index,
        deleted: delta.deleted > deletable ? deletable : delta.deleted,
        inserted: delta.inserted,
      );
    }

    _binding.push(() {
      final moved = _applyDelta(pushed, handlerText);

      // We know what we pushed, so the new text is the old one spliced — no
      // need to project the document again.
      _lastCommittedText = handlerText.replaceRange(
        pushed.index,
        pushed.index + pushed.deleted,
        pushed.inserted,
      );
      _lastCommittedRunes = handlerRunes - moved.deleted + moved.inserted;
      if (_lastCommittedText != _controller!.text) {
        // The rebase above merged remote content in: adopt it before a
        // postponed reset compares the two.
        _adopt(_lastCommittedText, runes: _lastCommittedRunes);
      }
    });
    _captureSelectionAnchors();
  }

  /// Folds one reported move into the field.
  ///
  /// [text] is the handler's whole text when it had to be read; [reported] is
  /// the delta when it did not. Exactly one of them is given.
  ///
  /// Done now rather than batched: taking a delta in costs the size of the
  /// edit, so waiting would only make the field lag behind the CRDT.
  void _settle({String? text, SequenceDelta<String>? reported}) {
    final base = text ?? _lastCommittedText;
    final runes = text != null
        ? RuneOffsets.length(text)
        : _lastCommittedRunes + _netRunes(reported);
    // Worked out from what the handler said it did, so the whole document is
    // never projected again for an edit of a few characters.
    final merged = reported == null ? base : reported.applyToText(base);

    if (_controller!.text != _lastCommittedText) {
      // Uncommitted local edits (a composition in progress): commit them
      // first. The handler merges them with what just arrived, and the push
      // adopts the result.
      _pushLocalEdits(handlerState: (text: merged, runes: runes));
      return;
    }

    // After a read the delta and the controller's text belong to different
    // bases, so the caret cannot ride on them — [reported] is null there.
    _adopt(merged, runes: runes, reported: reported);
  }

  /// Runes [delta] puts in, net of the ones it takes out.
  ///
  /// A move carries its element along, so it changes nothing here.
  static int _netRunes(SequenceDelta<String>? delta) {
    if (delta == null) {
      return 0;
    }
    var net = 0;
    for (final op in delta.ops) {
      switch (op) {
        case SeqInsert<String>():
          net += op.values.length;
        case SeqDelete<String>():
          net -= op.count;
        case SeqRetain<String>():
        case SeqMove<String>():
          break;
      }
    }
    return net;
  }

  /// Whether the field's text still agrees with the handler.
  ///
  /// The text is derived and never read back, so a mistake would leave a
  /// document on screen that does not exist until the next reset. This is the
  /// cheapest question that catches it; see
  /// [debugVerifyCrdtTextFieldProjection] for the strict version and the gap it
  /// closes.
  bool _projectionAgrees() {
    final handler = _handler();
    final agrees = handler is CRDTFugueTextHandler
        ? handler.length == _lastCommittedRunes
        : (handler as CRDTTextHandler).value == _lastCommittedText;
    assert(
      !debugVerifyCrdtTextFieldProjection ||
          _binding.provider.value == _lastCommittedText,
      'the text derived from the deltas drifted from the handler',
    );
    return agrees;
  }

  /// Replaces the controller text with [merged], keeping caret and selection
  /// visually anchored.
  ///
  /// Three ways to place an offset, best first:
  ///
  /// 1. its **stable position**, the identity of the element left of it, which
  ///    only a Fugue handler carries;
  /// 2. [reported], the delta the handler published, exact even when the change
  ///    touched several regions;
  /// 3. a diff of the two texts, which collapses several regions into one span.
  ///    Best-effort, and only used when the handler asked for a fresh read.
  void _adopt(
    String merged, {
    required int runes,
    SequenceDelta<String>? reported,
  }) {
    final old = _controller!.value;
    _lastCommittedText = merged;
    _lastCommittedRunes = runes;
    if (old.text == merged) {
      _captureSelectionAnchors();
      return;
    }

    final handler = _handler();
    TextDelta? diffed;
    int map(int offset, FugueElementID? anchor) {
      if (offset < 0) {
        // No selection (field never touched): keep it that way — turning it
        // into a caret would publish a phantom cursor on adopt.
        return offset;
      }
      if (anchor != null && handler is CRDTFugueTextHandler) {
        final resolved = handler.indexOfStablePosition(anchor);
        if (resolved != null) {
          // A rune index: back to a code-unit offset for the selection.
          return RuneOffsets.utf16Offset(merged, resolved);
        }
      }
      if (reported != null) {
        // The handler counts runes, the field counts code units.
        final rune = RuneOffsets.runeIndex(old.text, offset);
        return RuneOffsets.utf16Offset(merged, reported.mapOffset(rune))
            .clamp(0, merged.length);
      }
      diffed ??= computeTextDelta(old.text, merged)!;
      return mapOffsetThroughDelta(offset, diffed!).clamp(0, merged.length);
    }

    // A composition in progress spans code units that just moved. Carry it, or
    // a remote change throws away what the user is typing.
    var composing = TextRange.empty;
    if (old.composing.isValid) {
      final start = map(old.composing.start, null);
      final end = map(old.composing.end, null);
      if (start < end) {
        composing = TextRange(start: start, end: end);
      }
    }

    _controller!.value = TextEditingValue(
      text: merged,
      selection: TextSelection(
        baseOffset: map(old.selection.baseOffset, _selectionBaseAnchor),
        extentOffset: map(old.selection.extentOffset, _selectionExtentAnchor),
      ),
      composing: composing,
    );
    _captureSelectionAnchors();
  }
}
