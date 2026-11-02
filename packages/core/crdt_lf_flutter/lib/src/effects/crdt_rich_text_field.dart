// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/common/_crdt_guards.dart';
import 'package:crdt_lf_flutter/src/editor/crdt_editor_binding.dart';
import 'package:crdt_lf_flutter/src/effects/_text_field_core.dart';
import 'package:crdt_lf_flutter/src/effects/rich_text_editing_controller.dart';
import 'package:crdt_lf_flutter/src/effects/text_delta.dart';
import 'package:crdt_lf_flutter/src/provider/_crdt_view.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Whether [CrdtRichTextFieldBuilder] compares its whole content against the
/// handler.
///
/// After every step the field asks the handler for its length, which costs
/// nothing. A drift that keeps the length, in the text or in the formats, is
/// invisible to that question. While `true`, a debug build also compares the
/// text and the attributes of every rune, and throws on a mismatch. That
/// reads the whole value, the cost the field exists to avoid.
bool debugVerifyCrdtRichTextFieldProjection = true;

/// The origin of every write [CrdtRichTextFieldBuilder] makes to the handler.
///
/// Pass it in `trackedOrigins` to make a `CRDTUndoManager` record the edits
/// made in the field and nothing else.
const Object crdtRichTextFieldOrigin = Object();

typedef _HandlerState = ({List<RichTextSpan> spans, String text, int runes});

/// Binds a [CrdtRichTextEditingController] to the
/// [CRDTFugueRichTextHandler] registered under [id].
///
/// It works like `CrdtTextFieldBuilder`: local edits are pushed as the delta
/// of each gesture, an IME composition is committed when it ends, remote
/// changes are adopted in place with the caret kept, and the subtree never
/// rebuilds. On top of that:
///
/// - Text typed next to a formatted range takes the format when the range
///   expands there (see [MarkExpand]).
/// - [CrdtRichTextEditingController.format] formats the selection. At a
///   collapsed caret it styles the text typed next.
/// - The field paints inline formats only. Block attributes (headings,
///   lists), embeds and images need an editor, see `crdt_lf_quill`.
///
/// The field does one pass over the spans for each change, as a plain
/// `TextField` does for the text.
///
/// ## Example
/// ```dart
/// CrdtRichTextFieldBuilder(
///   id: 'note',
///   builder: (context, controller) => TextField(
///     controller: controller,
///     maxLines: null,
///     strutStyle: StrutStyle.disabled, // lines grow with the font size
///   ),
/// ),
/// ```
class CrdtRichTextFieldBuilder extends StatefulWidget {
  /// Creates a field bound to the rich text handler [id].
  const CrdtRichTextFieldBuilder({
    required this.id,
    required this.builder,
    this.styleOf = defaultRichAttributeStyle,
    this.undoManager,
    this.onSelectionAnchorsChanged,
    this.deletedBuilder,
    super.key,
  });

  /// The id of the [CRDTFugueRichTextHandler] to bind.
  final String id;

  /// Called once with the controller the field owns.
  final Widget Function(
    BuildContext context,
    CrdtRichTextEditingController controller,
  ) builder;

  /// The style of each run; see [defaultRichAttributeStyle].
  final RichAttributeStyle styleOf;

  /// The manager that undoes and redoes; `null` leaves undo to Flutter.
  ///
  /// Track the handler with it and pass [crdtRichTextFieldOrigin] in its
  /// `trackedOrigins`. Ctrl+Z (Cmd+Z on Apple platforms) and the redo
  /// shortcuts then go to the manager, and
  /// [CrdtRichTextEditingController.undo] and `redo` too. Undo takes back your
  /// own edits and formats only, and a peer's concurrent edit survives it.
  /// Flutter's own undo knows the text but not the formats, so it stays off.
  final CRDTUndoManager? undoManager;

  /// Called when the stable anchors of the selection change, while the field
  /// has focus.
  ///
  /// It fires once with `null`s when the focus leaves, or while an IME
  /// composition is pending. Publish the anchors to the other peers and draw
  /// them with `CrdtTextCursorsOverlay`.
  final void Function(FugueElementID? base, FugueElementID? extent)?
      onSelectionAnchorsChanged;

  /// {@macro crdt_deleted_builder}
  ///
  /// The published anchors are withdrawn with `null`s.
  final WidgetBuilder? deletedBuilder;

  @override
  State<CrdtRichTextFieldBuilder> createState() =>
      _CrdtRichTextFieldBuilderState();
}

class _CrdtRichTextFieldBuilderState extends State<CrdtRichTextFieldBuilder>
    implements CrdtRichTextEditingDelegate {
  CrdtRichTextEditingController? _controller;

  late CRDTDocument _document;

  late final CrdtEditorBinding<List<RichTextSpan>, RichTextDelta> _binding =
      CrdtEditorBinding<List<RichTextSpan>, RichTextDelta>(
    onReset: (spans, cause) {
      if (_seeding) {
        _seed(spans);
        return;
      }
      _settle(spans: spans);
    },
    onRemoteDelta: (event) => _settle(reported: event.delta),
    verifyProjection: _projectionAgrees,
    // An empty delta still has to commit a pending composition.
    skipEmptyDeltas: false,
  );

  bool _seeding = false;

  CRDTUndoManager? _manager;
  StreamSubscription<void>? _managerChanges;

  // Carried by arithmetic, so the projection check needs no count.
  int _committedRunes = 0;

  late final SelectionAnchors _anchors = SelectionAnchors(
    (base, extent) => widget.onSelectionAnchorsChanged?.call(base, extent),
  );

  // Where the pending attributes were set; they end when the caret leaves.
  FugueElementID? _pendingAnchor;

  CrdtRichTextEditingController get _c => _controller!;

  // Flutter maps no undo key on the web, where the browser undoes the text.
  static Map<ShortcutActivator, Intent> get _undoShortcuts {
    final apple = defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    const undo = UndoTextIntent(SelectionChangedCause.keyboard);
    const redo = RedoTextIntent(SelectionChangedCause.keyboard);
    return {
      SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: !apple,
        meta: apple,
      ): undo,
      SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: !apple,
        meta: apple,
        shift: true,
      ): redo,
      if (!apple)
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): redo,
    };
  }

  @override
  Widget build(BuildContext context) {
    final document = _document = context.liveDocument(
      'CrdtRichTextFieldBuilder',
    );
    if (context.selectCrdtDocument((doc) => doc.isDeleted(widget.id))) {
      _binding.detach();
      // Not here: the callback is the user's, and this is a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _anchors.clear();
        }
      });
      return buildDeleted(context, widget.deletedBuilder);
    }
    _seeding = true;
    try {
      _binding.attach(
        document,
        widget.id,
        onBeforeAttach: () => _anchors.clear(),
      );
    } finally {
      _seeding = false;
    }
    _c.styleOf = widget.styleOf;
    _followManager(widget.undoManager);
    final child = widget.builder(context, _c);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (hasFocus) => _anchors.hasFocus = hasFocus,
      child: _manager == null
          ? child
          : Shortcuts(
              shortcuts: _undoShortcuts,
              child: Actions(
                actions: {
                  UndoTextIntent: CallbackAction<UndoTextIntent>(
                    onInvoke: (_) => undo(),
                  ),
                  RedoTextIntent: CallbackAction<RedoTextIntent>(
                    onInvoke: (_) => redo(),
                  ),
                },
                child: child,
              ),
            ),
    );
  }

  @override
  void dispose() {
    unawaited(_managerChanges?.cancel());
    _binding.dispose();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  CRDTFugueRichTextHandler get _handler {
    final handler = _document.handlerById(widget.id);
    if (handler is CRDTFugueRichTextHandler) {
      return handler;
    }
    throw FlutterError(
      'CrdtRichTextFieldBuilder expected a CRDTFugueRichTextHandler '
      'registered under id "${widget.id}", but found ${handler ?? 'none'}.',
    );
  }

  void _seed(List<RichTextSpan> spans) {
    if (_controller == null) {
      _committedRunes = runesOfSpans(spans);
      _controller =
          CrdtRichTextEditingController(spans: spans, styleOf: widget.styleOf)
            ..delegate = this
            ..addListener(_onControllerChanged);
      return;
    }
    _adopt(spans, runes: runesOfSpans(spans));
  }

  // ------------------------------------------------------------- formatting

  bool get _canFormat =>
      _c.selection.isValid && _c.text == _c.spansText && !_binding.isBehind;

  @override
  Object? attributeAtSelection(String key) {
    if (!_canFormat) {
      return null;
    }
    final selection = _c.selection;
    final text = _c.spansText;
    if (selection.isCollapsed) {
      if (_pendingStillValid() && _c.pendingAttributes.containsKey(key)) {
        return _c.pendingAttributes[key];
      }
      final rune = RuneOffsets.runeIndex(text, selection.baseOffset);
      return rune == 0 ? null : _handler.attributesAt(rune - 1)[key];
    }
    final start = RuneOffsets.runeIndex(text, selection.start);
    final end = RuneOffsets.runeIndex(text, selection.end);
    final handler = _handler;
    final first = handler.attributesAt(start)[key];
    for (var i = start + 1; i < end; i++) {
      if (handler.attributesAt(i)[key] != first) {
        return null;
      }
    }
    return first;
  }

  @override
  void format(String key, Object? value, MarkExpand expand) {
    if (!_canFormat) {
      return;
    }
    final selection = _c.selection;
    final text = _c.spansText;
    if (selection.isCollapsed) {
      final current = _pendingStillValid()
          ? _c.pendingAttributes
          : const <String, Object?>{};
      _pendingAnchor = _handler.stablePositionAt(
        RuneOffsets.runeIndex(text, selection.baseOffset),
      );
      _c.pendingAttributes = {...current, key: value};
      return;
    }
    final start = RuneOffsets.runeIndex(text, selection.start);
    final length = RuneOffsets.runeIndex(text, selection.end) - start;
    // A format is a step of its own, not part of the typing before it.
    widget.undoManager?.stopCapturing();
    _binding.push(
      () {
        final handler = _handler;
        _document.runInTransaction(
          () => handler.format(start, length, key, value, expand: expand),
          origin: crdtRichTextFieldOrigin,
        );
        _c.setValueAndSpans(_c.value, handler.value);
      },
      isEcho: (dropped) => echoesRichText(dropped, deleted: 0, inserted: 0),
    );
  }

  // ------------------------------------------------------------------ undo

  void _followManager(CRDTUndoManager? manager) {
    if (identical(manager, _manager)) {
      return;
    }
    unawaited(_managerChanges?.cancel());
    _manager = manager;
    // The buttons of a toolbar listen to the controller.
    _managerChanges = manager?.changes.listen(
      (_) => _c.setValueAndSpans(_c.value, _c.spans),
    );
  }

  @override
  bool get canUndo => _manager?.canUndo ?? false;

  @override
  bool get canRedo => _manager?.canRedo ?? false;

  @override
  void undo() => _step(() => _manager!.undo());

  @override
  void redo() => _step(() => _manager!.redo());

  // The caret goes after the last change of the step, as Quill's history does.
  void _step(void Function() run) {
    if (!_canStep) {
      return;
    }
    _stepEnd = -1;
    try {
      run();
    } finally {
      final end = _stepEnd;
      _stepEnd = null;
      if (end != null && end >= 0 && _c.text == _c.spansText) {
        _c.selection = TextSelection.collapsed(
          offset: RuneOffsets.utf16Offset(_c.text, end),
        );
      }
    }
  }

  // Where the last delta of the running step ends, in runes; `null` outside a
  // step and `-1` before its first delta.
  int? _stepEnd;

  // A step written during a composition would land on text the handler does
  // not hold yet.
  bool get _canStep =>
      _manager != null && _c.text == _c.spansText && !_binding.isBehind;

  bool _pendingStillValid() {
    if (_c.pendingAttributes.isEmpty) {
      return false;
    }
    final selection = _c.selection;
    if (!selection.isCollapsed || selection.baseOffset < 0) {
      return false;
    }
    final rune = RuneOffsets.runeIndex(_c.text, selection.baseOffset);
    return _handler.stablePositionAt(rune) == _pendingAnchor;
  }

  // ------------------------------------------------------------ local edits

  void _onControllerChanged() {
    if (_document.isDeleted(widget.id)) {
      return;
    }
    final value = _c.value;
    if (value.text == _c.spansText) {
      if (_c.pendingAttributes.isNotEmpty && !_pendingStillValid()) {
        _c.pendingAttributes = const {};
      }
      _captureAnchors();
      return;
    }
    if (value.isComposingRangeValid) {
      _anchors.clear();
      return;
    }
    _pushLocalEdits();
  }

  void _pushLocalEdits({_HandlerState? handlerState}) {
    var known = handlerState;
    if (_binding.isBehind) {
      final spans = _binding.readSynced();
      known = (
        spans: spans,
        text: joinSpans(spans),
        runes: runesOfSpans(spans),
      );
    }
    final committedText = _c.spansText;
    final baseSpans = known?.spans ?? _c.spans;
    final baseText = known?.text ?? committedText;
    final baseRunes = known?.runes ?? _committedRunes;

    final selection = _c.selection;
    final caret = selection.isCollapsed ? selection.baseOffset : null;
    final delta = computeTextDelta(committedText, _c.text, caret: caret);
    if (delta == null) {
      if (known != null) {
        _adopt(baseSpans, runes: baseRunes);
      }
      return;
    }

    final pushed = baseText == committedText
        ? delta
        : rebaseDelta(delta, committedText, baseText);

    final index = RuneOffsets.runeIndex(baseText, pushed.index);
    final deleted = pushed.deleted == 0
        ? 0
        : RuneOffsets.runeIndex(baseText, pushed.index + pushed.deleted) -
            index;
    final pending = _c.pendingAttributes.isNotEmpty &&
            _handler.stablePositionAt(index) == _pendingAnchor
        ? _c.pendingAttributes
        : const <String, Object?>{};

    _binding.push(
      () {
        final handler = _handler;
        _document.runInTransaction(
          () {
            if (deleted > 0) {
              handler.delete(index, deleted);
            }
            _insert(handler, index, pushed.inserted, pending);
          },
          origin: crdtRichTextFieldOrigin,
        );
        final spans = RichTextDelta([
          RichTextRetain(index),
          RichTextDelete(deleted),
          ..._readInserted(handler, index, pushed.inserted),
        ]).apply(baseSpans);
        _committedRunes =
            baseRunes - deleted + RuneOffsets.length(pushed.inserted);
        if (joinSpans(spans) != _c.text) {
          _adopt(spans, runes: _committedRunes);
        } else {
          _c.setValueAndSpans(_c.value, spans);
        }
      },
      isEcho: (dropped) => echoesRichText(
        dropped,
        deleted: deleted,
        inserted: RuneOffsets.length(pushed.inserted),
      ),
    );
    _captureAnchors();
  }

  // A pending style stays off the newlines: the handler reads the attributes
  // of a '\n' as block attributes.
  static void _insert(
    CRDTFugueRichTextHandler handler,
    int index,
    String text,
    Map<String, Object?> pending,
  ) {
    if (text.isEmpty) {
      return;
    }
    if (pending.isEmpty) {
      handler.insert(index, text);
      return;
    }
    var at = index;
    for (final part in _splitNewlines(text)) {
      handler.insert(
        at,
        part,
        attributes: part == '\n' ? const {} : pending,
      );
      at += RuneOffsets.length(part);
    }
  }

  static Iterable<String> _splitNewlines(String text) sync* {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune == 0x0A) {
        if (buffer.isNotEmpty) {
          yield buffer.toString();
          buffer.clear();
        }
        yield '\n';
      } else {
        buffer.writeCharCode(rune);
      }
    }
    if (buffer.isNotEmpty) {
      yield buffer.toString();
    }
  }

  // The inserted runes with the attributes the handler gave them.
  static List<RichTextInsert> _readInserted(
    CRDTFugueRichTextHandler handler,
    int index,
    String text,
  ) {
    final out = <RichTextInsert>[];
    final buffer = StringBuffer();
    Map<String, Object?>? current;
    var rune = index;
    for (final codePoint in text.runes) {
      final attributes = handler.attributesAt(rune++);
      if (current != null && !mapEquals(current, attributes)) {
        out.add(RichTextInsert(buffer.toString(), current));
        buffer.clear();
      }
      current = attributes;
      buffer.writeCharCode(codePoint);
    }
    if (current != null) {
      out.add(RichTextInsert(buffer.toString(), current));
    }
    return out;
  }

  // ---------------------------------------------------------- remote edits

  void _settle({List<RichTextSpan>? spans, RichTextDelta? reported}) {
    final base = spans ?? _c.spans;
    final merged = reported == null ? base : reported.apply(base);
    if (_stepEnd != null && reported != null) {
      _stepEnd = _endOf(reported);
    }
    final runes = spans != null
        ? runesOfSpans(spans)
        : _committedRunes + _netRunes(reported);

    if (_c.text != _c.spansText) {
      _pushLocalEdits(
        handlerState: (spans: merged, text: joinSpans(merged), runes: runes),
      );
      return;
    }
    _adopt(merged, runes: runes, reported: reported);
  }

  // The rune after the last insert or retain of the delta.
  static int _endOf(RichTextDelta delta) {
    var end = 0;
    for (final op in delta.ops) {
      switch (op) {
        case RichTextInsert():
          end += op.length;
        case RichTextRetain():
          end += op.count;
        case RichTextDelete():
          break;
      }
    }
    return end;
  }

  // Runes the delta puts in, net of the ones it takes out.
  static int _netRunes(RichTextDelta? delta) {
    var net = 0;
    for (final op in delta?.ops ?? const <RichTextOp>[]) {
      switch (op) {
        case RichTextInsert():
          net += op.length;
        case RichTextDelete():
          net -= op.count;
        case RichTextRetain():
          break;
      }
    }
    return net;
  }

  bool _projectionAgrees() {
    final handler = _handler;
    assert(
      !debugVerifyCrdtRichTextFieldProjection ||
          (handler.text == _c.spansText &&
              sameRuneAttributes(handler.value, _c.spans)),
      'the spans derived from the deltas drifted from the handler',
    );
    return handler.length == _committedRunes;
  }

  void _adopt(
    List<RichTextSpan> merged, {
    required int runes,
    RichTextDelta? reported,
  }) {
    final old = _c.value;
    final mergedText = joinSpans(merged);
    _committedRunes = runes;
    if (old.text == mergedText) {
      // Formats only: same text and selection, new paint.
      _c.setValueAndSpans(old, merged);
      _captureAnchors();
      return;
    }

    final handler = _handler;
    _c.setValueAndSpans(
      adoptedValue(
        old: old,
        merged: mergedText,
        baseAnchor: _anchors.base,
        extentAnchor: _anchors.extent,
        resolve: handler.indexOfStablePosition,
        mapReported: reported?.mapOffset,
      ),
      merged,
    );
    _captureAnchors();
  }

  // ---------------------------------------------------------------- anchors

  void _captureAnchors() {
    if (_c.text != _c.spansText) {
      _anchors.clear();
      return;
    }
    _anchors.capture(_c.selection, _c.text, _handler.stablePositionAt);
  }
}
