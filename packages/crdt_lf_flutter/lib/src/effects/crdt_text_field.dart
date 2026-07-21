import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/effects/text_delta.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_helper.dart';
import 'package:flutter/widgets.dart';

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
///   element left of the caret — exact even when a remote change touches
///   several regions at once; otherwise the offsets are mapped through the
///   remote [TextDelta], best-effort.
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
  StreamSubscription<void>? _subscription;

  /// The handler-side text this widget has last pushed or adopted. Local
  /// deltas are computed against it.
  String _lastCommittedText = '';

  /// Swallows the echo of our own pushes in [_onDocumentUpdate].
  int _lastRevision = 0;

  /// Stable anchors ([CRDTFugueTextHandler.stablePositionAt]) for the current
  /// selection, captured whenever controller and handler agree. `null` while
  /// they diverge (a composition is pending) or for a non-Fugue handler —
  /// [_adopt] then falls back to [mapOffsetThroughDelta].
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
    _lastCommittedText = _handlerText();
    _lastRevision = document.revisionForHandler(widget.id);
    if (_controller == null) {
      _controller = TextEditingController(text: _lastCommittedText);
      _controller!.addListener(_onControllerChanged);
    } else {
      _adopt(_lastCommittedText);
    }
    _subscription = document.updates.listen((_) => _onDocumentUpdate());
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

  void _applyDelta(TextDelta delta) {
    final handler = _handler();
    void run() {
      if (handler is CRDTTextHandler) {
        if (delta.deleted > 0) {
          handler.delete(delta.index, delta.deleted);
        }
        if (delta.inserted.isNotEmpty) {
          handler.insert(delta.index, delta.inserted);
        }
      } else if (handler is CRDTFugueTextHandler) {
        if (delta.deleted > 0) {
          handler.delete(delta.index, delta.deleted);
        }
        if (delta.inserted.isNotEmpty) {
          handler.insert(delta.index, delta.inserted);
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
    _setSelectionAnchors(
      selection.baseOffset < 0
          ? null
          : handler.stablePositionAt(selection.baseOffset),
      selection.extentOffset < 0
          ? null
          : handler.stablePositionAt(selection.extentOffset),
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
    final handlerText = _handlerText();
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

    _applyDelta(pushed);
    _lastCommittedText = _handlerText();
    _lastRevision = _document!.revisionForHandler(widget.id);

    if (_lastCommittedText != _controller!.text) {
      // The rebase above merged remote content in: adopt it.
      _adopt(_lastCommittedText);
      return;
    }
    _captureSelectionAnchors();
  }

  /// Remote changes: adopt the merged value into the controller.
  void _onDocumentUpdate() {
    final document = _document!;
    final revision = document.revisionForHandler(widget.id);
    if (revision == _lastRevision) {
      return;
    }
    _lastRevision = revision;

    if (_controller!.text != _lastCommittedText) {
      // Uncommitted local edits (composition in progress): commit them first;
      // the handler merges them with the remote change, then we adopt.
      _pushLocalEdits();
      return;
    }
    _adopt(_handlerText());
  }

  /// Replaces the controller text with [merged], keeping caret and selection
  /// visually anchored: through their stable positions when available, else
  /// mapped through the delta.
  void _adopt(String merged) {
    final old = _controller!.value;
    _lastCommittedText = merged;
    if (old.text == merged) {
      return;
    }

    final handler = _handler();
    final delta = computeTextDelta(old.text, merged)!;
    int map(int offset, FugueElementID? anchor) {
      if (offset < 0) {
        // No selection (field never touched): keep it that way — turning it
        // into a caret would publish a phantom cursor on adopt.
        return offset;
      }
      if (anchor != null && handler is CRDTFugueTextHandler) {
        final resolved = handler.indexOfStablePosition(anchor);
        if (resolved != null) {
          return resolved.clamp(0, merged.length);
        }
      }
      return mapOffsetThroughDelta(offset, delta).clamp(0, merged.length);
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
