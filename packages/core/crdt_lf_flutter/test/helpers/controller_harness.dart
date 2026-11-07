// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:editor_conformance/editor_conformance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A plain text handler of `crdt_lf` seen by the editor suite.
class TextHandlerAccess implements ConformanceHandler {
  /// Wraps the text handler [raw].
  TextHandlerAccess(this.raw);

  @override
  final Handler<dynamic> raw;

  @override
  String get text => switch (raw) {
        final CRDTTextHandler handler => handler.value,
        final CRDTFugueTextHandler handler => handler.value,
        _ => throw StateError('not a text handler'),
      };

  @override
  int get length => RuneOffsets.length(text);

  @override
  void insert(int index, String text) => switch (raw) {
        final CRDTTextHandler handler => handler.insert(index, text),
        final CRDTFugueTextHandler handler => handler.insert(index, text),
        _ => throw StateError('not a text handler'),
      };

  @override
  void delete(int index, int count) => switch (raw) {
        final CRDTTextHandler handler => handler.delete(index, count),
        final CRDTFugueTextHandler handler => handler.delete(index, count),
        _ => throw StateError('not a text handler'),
      };

  @override
  Stream<Object?> watch() => switch (raw) {
        final CRDTTextHandler handler => handler.watch(),
        final CRDTFugueTextHandler handler => handler.watch(),
        _ => throw StateError('not a text handler'),
      };

  @override
  FugueElementID stablePositionAt(int index) =>
      (raw as CRDTFugueTextHandler).stablePositionAt(index);

  @override
  int? indexOfStablePosition(FugueElementID position) =>
      (raw as CRDTFugueTextHandler).indexOfStablePosition(position);

  @override
  void insertEmbed(int index, Map<String, Object?> embed) =>
      throw UnsupportedError('plain text has no embeds');

  @override
  void updateEmbed(int index, Map<String, Object?> embed) =>
      throw UnsupportedError('plain text has no embeds');

  @override
  Map<String, Object?>? embedAt(int index) =>
      throw UnsupportedError('plain text has no embeds');

  @override
  void format(int index, int count, String key, Object? value) =>
      throw UnsupportedError('plain text has no formats');

  @override
  Map<String, Object?> attributesAt(int index) =>
      throw UnsupportedError('plain text has no formats');
}

/// The editor suite harness of a field that hands out a
/// [TextEditingController].
class ControllerHarness extends EditorHarness {
  /// Creates a harness; [makeHandler] registers the handler under test and
  /// [buildField] is the field bound to it.
  ControllerHarness({
    required this.makeHandler,
    required this.buildField,
    this.supportsEmbeds = false,
    this.supportsAnchors = true,
    Object? origin,
  }) : _origin = origin;

  /// Registers the handler under test.
  final Handler<dynamic> Function(CRDTDocument document, String id) makeHandler;

  /// Builds the field; it must call `onController` with its controller each
  /// time it builds, publish its anchors to `onAnchors` and undo through
  /// `undoManager`.
  final Widget Function(
    String id,
    WidgetBuilder? deletedBuilder,
    void Function(TextEditingController controller) onController,
    SelectionAnchorsListener? onAnchors,
    CRDTUndoManager? undoManager,
  ) buildField;

  // The origin of the writes of a rich field; `null` for a plain one, which
  // neither undoes nor formats.
  final Object? _origin;

  @override
  Object get origin => _origin!;

  late TextEditingController _controller;

  @override
  bool get supportsComposition => true;

  @override
  final bool supportsEmbeds;

  @override
  final bool supportsAnchors;

  @override
  bool get supportsUndo => _origin != null;

  @override
  bool get supportsFormat => _origin != null;

  CrdtRichTextEditingController get _rich =>
      _controller as CrdtRichTextEditingController;

  @override
  ConformanceHandler createHandler(CRDTDocument document, String id) =>
      switch (makeHandler(document, id)) {
        final CRDTFugueRichTextHandler rich => RichTextHandlerAccess(rich),
        final plain => TextHandlerAccess(plain),
      };

  @override
  Widget build(
    CRDTDocument document,
    String id, {
    VoidCallback? onBuild,
    WidgetBuilder? deletedBuilder,
    SelectionAnchorsListener? onSelectionAnchorsChanged,
    CRDTUndoManager? undoManager,
  }) {
    return CrdtProvider.value(
      value: document,
      child: buildField(
        id,
        deletedBuilder,
        (controller) {
          _controller = controller;
          onBuild?.call();
        },
        onSelectionAnchorsChanged,
        undoManager,
      ),
    );
  }

  @override
  String get editorText => _controller.text;

  @override
  TextSelection get selection => _controller.selection;

  @override
  set selection(TextSelection value) => _controller.selection = value;

  @override
  void replaceText(int start, int end, String text) {
    _controller.value = TextEditingValue(
      text: _controller.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  @override
  void format(int start, int end, String key, Object? value) => _rich
    ..selection = TextSelection(baseOffset: start, extentOffset: end)
    ..format(key, value);

  @override
  void undo() => _rich.undo();

  @override
  void redo() => _rich.redo();

  @override
  Future<void> focus(WidgetTester tester) =>
      tester.showKeyboard(find.byType(TextField));

  @override
  Future<void> ime(WidgetTester tester, TextEditingValue value) async {
    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.updateEditingValue(value);
    await tester.pump();
  }
}
