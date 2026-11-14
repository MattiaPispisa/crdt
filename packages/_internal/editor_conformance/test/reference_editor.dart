// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:editor_conformance/editor_conformance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The origin of the writes of a [ReferenceBinding].
const Object referenceEditorOrigin = Object();

/// A local edit the handler does not hold yet.
///
/// It names the elements it touches, so it still lands in the right place
/// after a remote change moved them.
class Edit {
  Edit({
    required this.start,
    required this.count,
    required this.deleted,
    required this.at,
    required this.inserted,
  });

  /// The rune index of the edit when it was made.
  final int start;

  /// How many runes it deletes from [start].
  final int count;

  /// The elements it deletes, in text order.
  final List<FugueElementID> deleted;

  /// The anchor of a caret at [start].
  final FugueElementID at;

  /// The text it puts in their place.
  final String inserted;
}

/// The editor binding the suite is checked with: a `TextField` on a
/// [CRDTFugueRichTextHandler].
///
/// It is written to be easy to trust, not to be fast: on every change it
/// reads the whole text of the handler again. `broken_editors.dart` overrides
/// one member at a time to break one rule of the contract.
class ReferenceBinding {
  ReferenceBinding()
      : controller = TextEditingController(),
        focusNode = FocusNode();

  final TextEditingController controller;
  final FocusNode focusNode;

  late final CRDTDocument document;
  late final String id;
  late final CRDTFugueRichTextHandler handler;

  CRDTUndoManager? undoManager;
  SelectionAnchorsListener? onAnchors;
  VoidCallback rebuild = () {};

  bool deleted = false;
  bool writing = false;
  Edit? pending;
  (FugueElementID?, FugueElementID?) published = (null, null);

  bool _adopting = false;
  FugueElementID? _base;
  FugueElementID? _extent;
  StreamSubscription<Object?>? _changes;
  StreamSubscription<void>? _updates;

  Object? get origin => referenceEditorOrigin;

  bool get publishes => focusNode.hasFocus && pending == null;

  String get shown => controller.text;

  void attach(CRDTDocument document, String id) {
    this.document = document;
    this.id = id;
    handler = resolve(document, id);
    controller
      ..value = TextEditingValue(text: handler.text)
      ..addListener(onEdited);
    focusNode.addListener(publishAnchors);
    _changes = handler.watch().listen(onHandlerChanged);
    _updates = document.updates.listen((_) => onDocumentUpdated());
  }

  void dispose() {
    unawaited(_changes?.cancel());
    unawaited(_updates?.cancel());
    controller.dispose();
    focusNode.dispose();
  }

  CRDTFugueRichTextHandler resolve(CRDTDocument document, String id) {
    final found = document.registeredHandlers[id];
    if (found is! CRDTFugueRichTextHandler) {
      throw FlutterError('ReferenceEditor: "$id" holds no rich text handler');
    }
    return found;
  }

  int runeIndex(String text, int offset) => RuneOffsets.runeIndex(text, offset);

  int offsetOf(String text, int rune) => RuneOffsets.utf16Offset(text, rune);

  bool isComposing(TextEditingValue value) =>
      value.composing.isValid && !value.composing.isCollapsed;

  String writable(String inserted) => inserted.replaceAll('￼', '');

  void onEdited() {
    if (_adopting || deleted) {
      return;
    }
    final value = controller.value;
    pending = _diff(handler.text, value.text);
    if (pending == null) {
      _trackSelection();
      publishAnchors();
    } else if (isComposing(value)) {
      publishAnchors();
    } else {
      commit();
    }
  }

  /// Writes [pending] into the handler.
  void commit() {
    final edit = pending!;
    pending = null;
    final text = writable(edit.inserted);
    final deleted = deletedIndexes(edit);
    final at = insertIndex(edit);
    if (deleted.isNotEmpty || text.isNotEmpty) {
      write(() {
        deleted.forEach(writeDelete);
        if (text.isNotEmpty) {
          handler.insert(at, text);
        }
      });
    }
    _reconcile(caret: at + RuneOffsets.length(text));
    publishAnchors();
  }

  // Highest index first: a deletion leaves the indexes before it as they are.
  List<int> deletedIndexes(Edit edit) => [
        for (final element in edit.deleted.reversed)
          if (_isLive(element)) handler.indexOfStablePosition(element)! - 1,
      ];

  int insertIndex(Edit edit) {
    if (edit.deleted.isEmpty) {
      return handler.indexOfStablePosition(edit.at) ?? 0;
    }
    final first = edit.deleted.first;
    final after = handler.indexOfStablePosition(first) ?? 0;
    return _isLive(first) ? after - 1 : after;
  }

  void writeDelete(int index) => handler.delete(index, 1);

  void write(void Function() body) {
    writing = true;
    try {
      document.runInTransaction(body, origin: origin);
    } finally {
      writing = false;
    }
  }

  void format(int start, int end, String key, Object? value) {
    final text = controller.text;
    final from = runeIndex(text, start);
    closeUndoStep();
    write(() => handler.format(from, runeIndex(text, end) - from, key, value));
    closeUndoStep();
  }

  void closeUndoStep() => undoManager?.stopCapturing();

  void undo() => _step(() => undoManager?.undo());

  void redo() => _step(() => undoManager?.redo());

  int? stepCaret(String before, String after) {
    final edit = _diff(before, after);
    if (edit == null) {
      return null;
    }
    return offsetOf(after, edit.start + RuneOffsets.length(edit.inserted));
  }

  void onHandlerChanged(Object? event) {
    // A write hears its own echo, and what another watcher writes back, before
    // it returns: `commit` reads the handler once it has.
    if (writing || deleted || document.isDeleted(id)) {
      return;
    }
    // A remote change ends the composition: the edit goes in on top of it.
    if (pending != null) {
      commit();
      return;
    }
    final text = handler.text;
    if (text == shown) {
      return;
    }
    _adopt(text, mapSelection(text));
    publishAnchors();
  }

  void onDocumentUpdated() {
    if (!deleted && document.isDeleted(id)) {
      deleted = true;
      rebuild();
    }
  }

  TextSelection mapSelection(String text) {
    final base = _base;
    final extent = _extent;
    if (base == null || extent == null) {
      return const TextSelection.collapsed(offset: -1);
    }
    return TextSelection(
      baseOffset: offsetOf(text, handler.indexOfStablePosition(base) ?? 0),
      extentOffset: offsetOf(text, handler.indexOfStablePosition(extent) ?? 0),
    );
  }

  void publishAnchors() {
    final anchors = publishes ? (_base, _extent) : (null, null);
    if (anchors == published) {
      return;
    }
    published = anchors;
    onAnchors?.call(anchors.$1, anchors.$2);
  }

  void _step(void Function() run) {
    if (pending != null) {
      return;
    }
    final before = controller.text;
    writing = true;
    try {
      run();
    } finally {
      writing = false;
    }
    final after = handler.text;
    final caret = stepCaret(before, after);
    if (caret != null) {
      _adopt(after, TextSelection.collapsed(offset: caret));
    } else if (after != before) {
      _adopt(after, mapSelection(after));
    }
    publishAnchors();
  }

  void _reconcile({required int caret}) {
    final text = handler.text;
    if (text != controller.text) {
      _adopt(text, TextSelection.collapsed(offset: offsetOf(text, caret)));
    } else {
      _trackSelection();
    }
  }

  void _adopt(String text, TextSelection selection) {
    _adopting = true;
    try {
      controller.value = TextEditingValue(text: text, selection: selection);
    } finally {
      _adopting = false;
    }
    _trackSelection();
  }

  void _trackSelection() {
    final selection = controller.selection;
    if (!selection.isValid) {
      _base = _extent = null;
      return;
    }
    final text = controller.text;
    _base = handler.stablePositionAt(runeIndex(text, selection.baseOffset));
    _extent = handler.stablePositionAt(runeIndex(text, selection.extentOffset));
  }

  bool _isLive(FugueElementID element) {
    final after = handler.indexOfStablePosition(element);
    return after != null && after > 0 && handler.nodeAt(after - 1) == element;
  }

  Edit? _diff(String from, String to) {
    if (from == to) {
      return null;
    }
    // The shared ends stop at a rune boundary, or half an emoji would count
    // as unchanged.
    final shared = min(from.length, to.length);
    var prefix = 0;
    while (
        prefix < shared && from.codeUnitAt(prefix) == to.codeUnitAt(prefix)) {
      prefix++;
    }
    if (RuneOffsets.splitsPair(from, prefix) ||
        RuneOffsets.splitsPair(to, prefix)) {
      prefix--;
    }
    var suffix = 0;
    while (suffix < shared - prefix &&
        from.codeUnitAt(from.length - 1 - suffix) ==
            to.codeUnitAt(to.length - 1 - suffix)) {
      suffix++;
    }
    if (RuneOffsets.splitsPair(from, from.length - suffix) ||
        RuneOffsets.splitsPair(to, to.length - suffix)) {
      suffix--;
    }
    final start = runeIndex(from, prefix);
    final count = runeIndex(from, from.length - suffix) - start;
    return Edit(
      start: start,
      count: count,
      deleted: [
        for (var index = start; index < start + count; index++)
          handler.nodeAt(index),
      ],
      at: handler.stablePositionAt(start),
      inserted: to.substring(prefix, to.length - suffix),
    );
  }
}

/// The widget of a [ReferenceBinding]; it rebuilds only when the handler is
/// deleted.
class ReferenceEditor extends StatefulWidget {
  const ReferenceEditor({
    required this.binding,
    required this.document,
    required this.id,
    this.onBuild,
    this.deletedBuilder,
    this.onSelectionAnchorsChanged,
    this.undoManager,
    super.key,
  });

  final ReferenceBinding binding;
  final CRDTDocument document;
  final String id;
  final VoidCallback? onBuild;
  final WidgetBuilder? deletedBuilder;
  final SelectionAnchorsListener? onSelectionAnchorsChanged;
  final CRDTUndoManager? undoManager;

  @override
  State<ReferenceEditor> createState() => _ReferenceEditorState();
}

class _ReferenceEditorState extends State<ReferenceEditor> {
  @override
  void initState() {
    super.initState();
    widget.binding
      ..undoManager = widget.undoManager
      ..onAnchors = widget.onSelectionAnchorsChanged
      ..rebuild = () {
        if (mounted) {
          setState(() {});
        }
      }
      ..attach(widget.document, widget.id);
  }

  @override
  void dispose() {
    widget.binding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final binding = widget.binding;
    if (binding.deleted) {
      return widget.deletedBuilder?.call(context) ?? const SizedBox.shrink();
    }
    widget.onBuild?.call();
    return TextField(
      controller: binding.controller,
      focusNode: binding.focusNode,
      maxLines: null,
    );
  }
}

/// The harness of the reference editor, or of a binding that breaks it.
class ReferenceHarness extends EditorHarness {
  ReferenceHarness([ReferenceBinding Function() create = ReferenceBinding.new])
      : _binding = create();

  final ReferenceBinding _binding;

  @override
  bool get supportsComposition => true;

  @override
  bool get supportsEmbeds => true;

  @override
  bool get supportsAnchors => true;

  @override
  bool get supportsUndo => true;

  @override
  bool get supportsFormat => true;

  @override
  Object get origin => referenceEditorOrigin;

  Finder get _field => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller == _binding.controller,
      );

  @override
  ConformanceHandler createHandler(CRDTDocument document, String id) =>
      RichTextHandlerAccess(CRDTFugueRichTextHandler(document, id));

  @override
  Widget build(
    CRDTDocument document,
    String id, {
    VoidCallback? onBuild,
    WidgetBuilder? deletedBuilder,
    SelectionAnchorsListener? onSelectionAnchorsChanged,
    CRDTUndoManager? undoManager,
  }) {
    return ReferenceEditor(
      // The suite mounts a new editor where the last one was: without a key
      // the old state, and its binding, would stay.
      key: ObjectKey(_binding),
      binding: _binding,
      document: document,
      id: id,
      onBuild: onBuild,
      deletedBuilder: deletedBuilder,
      onSelectionAnchorsChanged: onSelectionAnchorsChanged,
      undoManager: undoManager,
    );
  }

  @override
  String get editorText => _binding.controller.text;

  @override
  TextSelection get selection => _binding.controller.selection;

  @override
  set selection(TextSelection value) => _binding.controller.selection = value;

  @override
  void replaceText(int start, int end, String text) {
    _binding.controller.value = TextEditingValue(
      text: editorText.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  @override
  void format(int start, int end, String key, Object? value) =>
      _binding.format(start, end, key, value);

  @override
  void undo() => _binding.undo();

  @override
  void redo() => _binding.redo();

  @override
  Future<void> focus(WidgetTester tester) => tester.showKeyboard(_field);

  @override
  Future<void> ime(WidgetTester tester, TextEditingValue value) async {
    await tester.showKeyboard(_field);
    tester.testTextInput.updateEditingValue(value);
    await tester.pump();
  }
}
