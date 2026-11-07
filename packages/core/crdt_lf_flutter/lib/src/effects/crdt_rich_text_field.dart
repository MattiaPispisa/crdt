// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/common/_crdt_guards.dart';
import 'package:crdt_lf_flutter/src/editor/rich_text_echoes.dart';
import 'package:crdt_lf_flutter/src/editor/rich_text_writer.dart';
import 'package:crdt_lf_flutter/src/editor/selection_anchors.dart';
import 'package:crdt_lf_flutter/src/effects/_text_field_engine.dart';
import 'package:crdt_lf_flutter/src/effects/text_delta.dart';
import 'package:crdt_lf_flutter/src/provider/_crdt_view.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_helper.dart';
import 'package:crdt_lf_flutter/src/provider/handler_delta_subscription.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

part 'rich_text_editing_controller.dart';

/// Whether [CrdtRichTextFieldBuilder] compares its whole content against the
/// handler.
///
/// After every step the field asks the handler for its length, which costs
/// nothing. A drift that keeps the length, in the text, the formats or the
/// embeds, is invisible to that question. While `true`, a debug build also
/// compares the text, the attributes and the embed of every rune, and throws
/// on a mismatch. That reads the whole value, the cost the field exists to
/// avoid.
bool debugVerifyCrdtRichTextFieldProjection = true;

/// The origin of every write [CrdtRichTextFieldBuilder] makes to the handler.
///
/// Pass it in `trackedOrigins` to make a `CRDTUndoManager` record the edits
/// made in the field and nothing else.
const Object crdtRichTextFieldOrigin = Object();

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
///   lists) and the content of embeds need an editor, see `crdt_lf_quill`.
/// - An embed shows as its U+FFFC glyph and stays intact through edits
///   around it, deletes, undo and remote changes, its data included. The
///   field strips a typed or pasted U+FFFC: the handler refuses it as text.
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
    implements
        _CrdtRichTextEditingDelegate,
        TextFieldContent<List<RichTextSpan>, RichTextDelta>,
        EmbedFieldContent<List<RichTextSpan>> {
  late CRDTDocument _document;

  late final TextFieldEngine<List<RichTextSpan>, RichTextDelta> _engine =
      TextFieldEngine<List<RichTextSpan>, RichTextDelta>(
    this,
    publish: (base, extent) =>
        widget.onSelectionAnchorsChanged?.call(base, extent),
    resolve: (document, id) =>
        resolveDeltaProvider<List<RichTextSpan>, RichTextDelta>(
      document,
      id,
      'CrdtRichTextFieldBuilder',
    ),
  );

  CrdtRichTextEditingController? _controller;

  CRDTUndoManager? _manager;
  StreamSubscription<void>? _managerChanges;

  // What the running write puts on the text it inserts.
  RichTextEcho? _written;

  // Where the pending attributes were set; they end when the caret leaves.
  FugueElementID? _pendingAnchor;

  // The expand mode of each pending key; a key missing here expands after.
  Map<String, MarkExpand> _pendingExpand = const {};

  late final RichTextWriter _writer = RichTextWriter(
    expandOf: (key) => _pendingExpand[key] ?? MarkExpand.after,
  );

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
      _engine.binding.detach();
      _engine.anchors.clearAfterFrame(mounted: () => mounted);
      return buildDeleted(context, widget.deletedBuilder);
    }
    _engine.attach(document, widget.id, onBeforeAttach: _dropPending);
    _c.styleOf = widget.styleOf;
    _followManager(widget.undoManager);
    final child = widget.builder(context, _c);
    return SelectionAnchorsFocus(
      anchors: _engine.anchors,
      // Always in the tree, empty without a manager: adding one later must
      // not remount the user's field and lose its focus.
      child: Shortcuts(
        shortcuts: _manager == null ? const {} : _undoShortcuts,
        child: Actions(
          actions: _manager == null
              ? const {}
              : {
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
    _engine.dispose();
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

  // ------------------------------------------------------------- formatting

  bool get _canFormat =>
      _c.selection.isValid &&
      _c.text == _c.spansText &&
      !_engine.binding.isBehind;

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
    // The spans are the handler's, in code units like the selection: one look
    // per run instead of one per rune.
    Object? first;
    var seen = false;
    var offset = 0;
    for (final span in _c.spans) {
      final end = offset + span.text.length;
      if (end > selection.start) {
        final value = span.attributes[key];
        if (seen && value != first) {
          return null;
        }
        first = value;
        seen = true;
      }
      offset = end;
      if (offset >= selection.end) {
        break;
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
      _handler.checkAttribute(value);
      final valid = _pendingStillValid();
      final current = valid ? _c.pendingAttributes : const <String, Object?>{};
      _pendingExpand = {if (valid) ..._pendingExpand, key: expand};
      _pendingAnchor = _handler.stablePositionAt(
        RuneOffsets.runeIndex(text, selection.baseOffset),
      );
      _c._setPending({...current, key: value});
      return;
    }
    final start = RuneOffsets.runeIndex(text, selection.start);
    final length = RuneOffsets.runeIndex(text, selection.end) - start;
    _engine.binding.push(
      () {
        final handler = _handler;
        _document.runInTransaction(
          () => handler.format(start, length, key, value, expand: expand),
          origin: crdtRichTextFieldOrigin,
        );
        _engine.reformat(handler.value);
      },
      isEcho: (dropped) => echoesRichText(
        dropped,
        deleted: 0,
        inserted: 0,
        ownsFormat: formatsWithin(start, start + length, {key: value}),
      ),
      ownStep: widget.undoManager,
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
      (_) => _c._setValueAndSpans(_c.value, _c.spans),
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
      _manager != null && _c.text == _c.spansText && !_engine.binding.isBehind;

  void _dropPending() {
    _controller?._pending = const {};
    _pendingExpand = const {};
    _pendingAnchor = null;
  }

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

  // ----------------------------------------------------- TextFieldContent

  @override
  TextEditingController createController(List<RichTextSpan> content) =>
      _controller = CrdtRichTextEditingController._(
        spans: content,
        styleOf: widget.styleOf,
      ).._delegate = this;

  @override
  String textOf(List<RichTextSpan> content) => _joinSpans(content);

  @override
  int runesOf(List<RichTextSpan> content) => _runesOfSpans(content);

  @override
  List<RichTextSpan> apply(List<RichTextSpan> base, RichTextDelta delta) =>
      delta.apply(base);

  // Runes the delta puts in, net of the ones it takes out.
  @override
  int netRunes(RichTextDelta delta) {
    var net = 0;
    for (final op in delta.ops) {
      switch (op) {
        case RichTextInsert() || RichTextInsertEmbed():
          net += op.length;
        case RichTextDelete():
          net -= op.count;
        case RichTextRetain() || RichTextUpdateEmbed():
          break;
      }
    }
    return net;
  }

  @override
  int Function(int rune) offsetMapper(RichTextDelta delta) => delta.mapOffset;

  @override
  List<RichTextSpan> write(
    List<RichTextSpan> base,
    String baseText,
    TextDelta pushed,
    int index,
    int deleted,
  ) {
    final handler = _handler;
    final written = _written = RichTextEcho(_writer);
    final ops = _document.runInTransaction(
      () => _writeRegion(handler, written, pushed.inserted, index, deleted, 0),
      origin: crdtRichTextFieldOrigin,
    );
    return RichTextDelta(ops).apply(base);
  }

  @override
  List<RichTextSpan> writeRegions(
    List<RichTextSpan> base,
    String baseText,
    List<TextRegion> regions,
  ) {
    final handler = _handler;
    final written = _written = RichTextEcho(_writer);
    final ops = <RichTextOp>[];
    var at = 0;
    _document.runInTransaction(
      () {
        for (final (:pushed, :index, :deleted) in regions) {
          final text = pushed.inserted;
          ops.addAll(_writeRegion(handler, written, text, index, deleted, at));
          at = index + RuneOffsets.length(text);
        }
      },
      origin: crdtRichTextFieldOrigin,
    );
    return RichTextDelta(ops).apply(base);
  }

  // Writes one edit and returns its ops, retained from the rune [from]. Read
  // in the transaction: the flush runs listeners, which may change the text.
  List<RichTextOp> _writeRegion(
    CRDTFugueRichTextHandler handler,
    RichTextEcho written,
    String text,
    int index,
    int deleted,
    int from,
  ) {
    final pending = _pendingAt(handler, index);
    if (pending.isNotEmpty) {
      written.add(
        RichTextDelta([RichTextRetain(index), RichTextInsert(text, pending)]),
      );
    }
    if (deleted > 0) {
      handler.delete(index, deleted);
    }
    return [
      RichTextRetain(index - from),
      RichTextDelete(deleted),
      ..._writer.insertTyped(handler, index, text, pending),
    ];
  }

  // The pending attributes, when the caret that set them is at [index].
  Map<String, Object?> _pendingAt(
    CRDTFugueRichTextHandler handler,
    int index,
  ) =>
      _c.pendingAttributes.isNotEmpty &&
              handler.stablePositionAt(index) == _pendingAnchor
          ? _c.pendingAttributes
          : const <String, Object?>{};

  @override
  bool echoes(
    List<RichTextDelta> dropped, {
    required int deleted,
    required int inserted,
  }) =>
      echoesRichText(
        dropped,
        deleted: deleted,
        inserted: inserted,
        ownsFormat: _written?.ownsFormat,
      );

  @override
  String writable(String typed) =>
      typed.replaceAll(RichTextSpan.objectReplacement, '');

  @override
  void show(TextEditingValue value, List<RichTextSpan> content) {
    _c._setValueAndSpans(value, content);
  }

  @override
  void showFormats(List<RichTextSpan> content) {
    _c._setValueAndSpans(_c.value, content);
  }

  @override
  bool projectionAgrees() {
    final handler = _handler;
    assert(
      !debugVerifyCrdtRichTextFieldProjection ||
          (handler.text == _c.spansText &&
              sameRuneAttributes(handler.value, _c.spans)),
      'the spans derived from the deltas drifted from the handler',
    );
    return handler.length == _engine.committedRunes;
  }

  @override
  bool get anchored => true;

  @override
  FugueElementID? anchorAt(int rune) => _handler.stablePositionAt(rune);

  @override
  int? runeOf(FugueElementID anchor) => _handler.indexOfStablePosition(anchor);

  @override
  void remoteReported(RichTextDelta delta) {
    if (_stepEnd != null && delta.isNotEmpty) {
      _stepEnd = delta.changeEnd;
    }
  }

  @override
  void selectionSettled() {
    if (_c.pendingAttributes.isNotEmpty && !_pendingStillValid()) {
      _c._setPending(const {});
    }
  }
}
