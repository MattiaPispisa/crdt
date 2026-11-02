// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/common/_crdt_guards.dart';
import 'package:crdt_lf_flutter/src/effects/_text_field_core.dart';
import 'package:crdt_lf_flutter/src/effects/_text_field_engine.dart';
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
    implements
        CrdtRichTextEditingDelegate,
        TextFieldContent<List<RichTextSpan>, RichTextDelta> {
  late CRDTDocument _document;

  late final TextFieldEngine<List<RichTextSpan>, RichTextDelta> _engine =
      TextFieldEngine<List<RichTextSpan>, RichTextDelta>(
    this,
    publish: (base, extent) =>
        widget.onSelectionAnchorsChanged?.call(base, extent),
  );

  CRDTUndoManager? _manager;
  StreamSubscription<void>? _managerChanges;

  // Where the pending attributes were set; they end when the caret leaves.
  FugueElementID? _pendingAnchor;

  CrdtRichTextEditingController get _c =>
      _engine.controller as CrdtRichTextEditingController;

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
      // Not here: the callback is the user's, and this is a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _engine.anchors.clear();
        }
      });
      return buildDeleted(context, widget.deletedBuilder);
    }
    _engine.attach(document, widget.id);
    _c.styleOf = widget.styleOf;
    _followManager(widget.undoManager);
    final child = widget.builder(context, _c);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (hasFocus) => _engine.anchors.hasFocus = hasFocus,
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
    _engine.binding.push(
      () {
        final handler = _handler;
        _document.runInTransaction(
          () => handler.format(start, length, key, value, expand: expand),
          origin: crdtRichTextFieldOrigin,
        );
        _engine.reformat(handler.value);
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
      _manager != null && _c.text == _c.spansText && !_engine.binding.isBehind;

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
      CrdtRichTextEditingController(spans: content, styleOf: widget.styleOf)
        ..delegate = this;

  @override
  String textOf(List<RichTextSpan> content) => joinSpans(content);

  @override
  int runesOf(List<RichTextSpan> content) => runesOfSpans(content);

  @override
  List<RichTextSpan> apply(List<RichTextSpan> base, RichTextDelta delta) =>
      delta.apply(base);

  // Runes the delta puts in, net of the ones it takes out.
  @override
  int netRunes(RichTextDelta delta) {
    var net = 0;
    for (final op in delta.ops) {
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
    final pending = _c.pendingAttributes.isNotEmpty &&
            handler.stablePositionAt(index) == _pendingAnchor
        ? _c.pendingAttributes
        : const <String, Object?>{};
    _document.runInTransaction(
      () {
        if (deleted > 0) {
          handler.delete(index, deleted);
        }
        _insert(handler, index, pushed.inserted, pending);
      },
      origin: crdtRichTextFieldOrigin,
    );
    return RichTextDelta([
      RichTextRetain(index),
      RichTextDelete(deleted),
      ..._readInserted(handler, index, pushed.inserted),
    ]).apply(base);
  }

  @override
  bool echoes(
    List<RichTextDelta> dropped, {
    required int deleted,
    required int inserted,
  }) =>
      echoesRichText(dropped, deleted: deleted, inserted: inserted);

  @override
  void show(TextEditingValue value, List<RichTextSpan> content) {
    _c.setValueAndSpans(value, content);
  }

  @override
  void showFormats(List<RichTextSpan> content) {
    _c.setValueAndSpans(_c.value, content);
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
    if (_stepEnd != null) {
      _stepEnd = _endOf(delta);
    }
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

  @override
  void selectionSettled() {
    if (_c.pendingAttributes.isNotEmpty && !_pendingStillValid()) {
      _c.pendingAttributes = const {};
    }
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
}
