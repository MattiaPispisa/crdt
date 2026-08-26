import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/effects/text_delta.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_helper.dart';
import 'package:flutter/widgets.dart';

/// Whether [CrdtTextFieldBuilder] checks its text against the handler.
///
/// The field keeps its text by moving it with the deltas the handler reports,
/// instead of projecting the whole document again after every edit. That is
/// what makes a keystroke cost the size of the edit rather than the size of
/// the document.
///
/// While this is `true` — and only in a debug build — every adopt reads the
/// handler and compares, so a binding that drifts fails loudly instead of
/// quietly showing the wrong text. **That read is the very cost the field
/// avoids**, so a benchmark measuring release behaviour has to turn it off.
/// Nothing else should.
bool debugVerifyCrdtTextFieldProjection = true;

/// {@template crdt_text_field_builder}
/// Binds a [TextEditingController] to the text handler registered under [id]
/// (`CRDTTextHandler` or `CRDTFugueTextHandler`), the way collaborative
/// editor bindings (e.g. Yjs) do:
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

  @override
  State<CrdtTextFieldBuilder> createState() => _CrdtTextFieldBuilderState();
}

class _CrdtTextFieldBuilderState extends State<CrdtTextFieldBuilder> {
  TextEditingController? _controller;
  CRDTDocument? _document;
  StreamSubscription<HandlerUpdate<SequenceDelta<String>>>? _subscription;

  /// The handler-side text this widget has last pushed or adopted. Local
  /// deltas are computed against it.
  String _lastCommittedText = '';

  /// What the handler reported since the last adopt, composed into one delta.
  ///
  /// The handler publishes one event per change, so a sync burst produces
  /// several. Composing them and adopting once keeps the controller written
  /// exactly once per settled batch, as it was when this listened to
  /// `document.updates`.
  SequenceDelta<String>? _pendingDelta;

  /// The text read when the handler asked for one, waiting to be adopted.
  ///
  /// A reset means no delta describes the move, so this is the only way back
  /// in step — and the caret falls back to being mapped through a diff.
  String? _resyncText;

  /// The point of the delta stream the widget has taken in.
  int _syncedSeq = -1;

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
    final document = context.crdtDocument;
    if (!identical(document, _document)) {
      _attach(document);
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
    _subscription?.cancel();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  void _attach(CRDTDocument document) {
    _subscription?.cancel();
    _document = document;
    _invalidateSelectionAnchors();
    _pendingDelta = null;
    _resyncText = null;
    final provider = _deltaProvider();
    _lastCommittedText = provider.value;
    _syncedSeq = provider.deltaSeq;
    if (_controller == null) {
      _controller = TextEditingController(text: _lastCommittedText);
      _controller!.addListener(_onControllerChanged);
    } else {
      _adopt(_lastCommittedText);
    }
    // The handler's own stream, not `document.updates`: it says **what** each
    // change did, which is what places the caret exactly.
    _subscription = _deltaProvider().watch().listen(_onHandlerUpdate);
  }

  DeltaProvider<String, SequenceDelta<String>> _deltaProvider() {
    final handler = _handler();
    // Both text handlers publish this shape; [_handler] refuses anything else.
    return handler as DeltaProvider<String, SequenceDelta<String>>;
  }

  Handler<dynamic> _handler() {
    final handler = _document!.registeredHandlers[widget.id];
    if (handler is CRDTTextHandler || handler is CRDTFugueTextHandler) {
      return handler!;
    }
    throw FlutterError(
      'CrdtTextFieldBuilder expected a CRDTTextHandler or '
      'CRDTFugueTextHandler registered under id "${widget.id}", '
      'but found ${handler ?? 'none'}.',
    );
  }

  String _handlerText() {
    final handler = _handler();
    if (handler is CRDTTextHandler) {
      return handler.value;
    }
    return (handler as CRDTFugueTextHandler).value;
  }

  /// Pushes [delta] into the handler. Its offsets are code-unit offsets into
  /// [against], the handler's text as the delta was computed against it.
  void _applyDelta(TextDelta delta, String against) {
    final handler = _handler();

    // [TextDelta] is expressed in code units, the handlers in runes. The
    // delta's boundaries are snapped to code-point boundaries by
    // [computeTextDelta], so both ends convert exactly.
    final index = RuneOffsets.runeIndex(against, delta.index);
    final deleted = delta.deleted == 0
        ? 0
        : RuneOffsets.runeIndex(against, delta.index + delta.deleted) - index;

    void run() {
      if (handler is CRDTTextHandler) {
        if (deleted > 0) {
          handler.delete(index, deleted);
        }
        if (delta.inserted.isNotEmpty) {
          handler.insert(index, delta.inserted);
        }
      } else if (handler is CRDTFugueTextHandler) {
        if (deleted > 0) {
          handler.delete(index, deleted);
        }
        if (delta.inserted.isNotEmpty) {
          handler.insert(index, delta.inserted);
        }
      }
    }

    _document!.runInTransaction(run);
  }

  /// Captures the stable anchors of the current selection.
  ///
  /// Only meaningful when the controller text matches the handler text (the
  /// offsets must be valid in the handler's coordinates).
  void _captureSelectionAnchors() {
    final handler = _document!.registeredHandlers[widget.id];
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

  void _pushLocalEdits() {
    final provider = _deltaProvider();

    // What the handler holds is what we hold, unless it moved and we have not
    // folded that in yet — which is what is still waiting here, not what the
    // stream has merely announced. Both cases are answered without projecting
    // the document again: a reset already carries its text, and a delta says
    // what to do to ours.
    final resyncText = _resyncText;
    final pending = _pendingDelta;
    _resyncText = null;
    _pendingDelta = null;

    final base = resyncText ?? _lastCommittedText;
    final handlerText = pending == null ? base : pending.applyToText(base);

    final target = _controller!.text;

    // The post-edit caret disambiguates edits inside a run of identical
    // characters (e.g. a newline typed right before another newline), so the
    // gesture is recorded where the user actually is, not slid past it.
    final selection = _controller!.selection;
    final caret = selection.isCollapsed ? selection.baseOffset : null;
    final delta = computeTextDelta(_lastCommittedText, target, caret: caret);
    if (delta == null) {
      _lastCommittedText = target;
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

    _applyDelta(pushed, handlerText);

    // We know what we pushed, so the new text is the old one with that splice
    // applied — no need to project the document again to find out.
    _lastCommittedText = handlerText.replaceRange(
      pushed.index,
      pushed.index + pushed.deleted,
      pushed.inserted,
    );
    // The change published its events while it was applied, so this covers
    // our own echo: [_onHandlerUpdate] will skip it instead of applying the
    // edit a second time.
    _syncedSeq = provider.deltaSeq;
    _pendingDelta = null;
    assert(
      !debugVerifyCrdtTextFieldProjection ||
          _handlerText() == _lastCommittedText,
      'the text derived from the deltas drifted from the handler',
    );

    if (_lastCommittedText != _controller!.text) {
      // The rebase above merged remote content in: adopt it.
      _adopt(_lastCommittedText);
      return;
    }
    _captureSelectionAnchors();
  }

  /// Takes in what the handler reports, one change at a time.
  ///
  /// The work is done here and now rather than booked for later: a change is
  /// now described by a delta, so taking it in costs the size of the edit, not
  /// the size of the document. There is nothing left worth batching, and
  /// waiting would only make the field lag behind the CRDT.
  void _onHandlerUpdate(HandlerUpdate<SequenceDelta<String>> update) {
    switch (update) {
      case HandlerReset<SequenceDelta<String>>():
        // The base the deltas described was replaced, so this is the one place
        // that has to read the whole value again. Keep it: reading it twice
        // would cost a second projection of the entire document.
        final point = _deltaProvider().readSynced();
        _pendingDelta = null;
        _resyncText = point.value;
        _syncedSeq = point.seq;
      case HandlerDelta<SequenceDelta<String>>():
        if (update.seq <= _syncedSeq) {
          // Already inside the text the last read handed over.
          return;
        }
        _syncedSeq = update.seq;
        final pending = _pendingDelta;
        _pendingDelta =
            pending == null ? update.delta : pending.compose(update.delta);
    }
    _settle();
  }

  void _settle() {
    if (_controller!.text != _lastCommittedText) {
      // Uncommitted local edits (composition in progress): commit them first;
      // the handler merges them with the remote change, then we adopt. It
      // reads what is waiting, so nothing is cleared here.
      _pushLocalEdits();
      return;
    }

    final reported = _pendingDelta;
    final resyncText = _resyncText;
    _pendingDelta = null;
    _resyncText = null;

    // The new text is worked out from what the handler said it did, so the
    // whole document is never projected again for an edit of a few characters.
    final base = resyncText ?? _lastCommittedText;
    final merged = reported == null ? base : reported.applyToText(base);

    // After a reset the deltas and the controller's text belong to different
    // bases, so the caret cannot ride on them.
    _adopt(merged, reported: resyncText != null ? null : reported);
  }

  /// Replaces the controller text with [merged], keeping caret and selection
  /// visually anchored.
  ///
  /// Three ways to place an offset, best first:
  ///
  /// 1. its **stable position** — the identity of the element left of it,
  ///    which only a Fugue handler carries;
  /// 2. the **delta the handler reported**, [reported], which says exactly
  ///    what moved even when the change touched several regions;
  /// 3. a diff of the two texts, which collapses several regions into one
  ///    span and can only be best-effort. This is the last resort, used when
  ///    the handler asked for a fresh read instead of reporting a move.
  void _adopt(String merged, {SequenceDelta<String>? reported}) {
    final old = _controller!.value;
    _lastCommittedText = merged;
    if (old.text == merged) {
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

    _controller!.value = TextEditingValue(
      text: merged,
      selection: TextSelection(
        baseOffset: map(old.selection.baseOffset, _selectionBaseAnchor),
        extentOffset: map(old.selection.extentOffset, _selectionExtentAnchor),
      ),
    );
    _captureSelectionAnchors();
  }
}
