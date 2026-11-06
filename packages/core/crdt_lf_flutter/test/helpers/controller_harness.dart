// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:editor_conformance/editor_conformance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A handler of `crdt_lf` seen by the editor suite.
class TextHandlerAccess implements ConformanceHandler {
  /// Wraps the text handler [raw].
  TextHandlerAccess(this.raw);

  @override
  final Handler<dynamic> raw;

  @override
  String get text => switch (raw) {
        final CRDTTextHandler handler => handler.value,
        final CRDTFugueTextHandler handler => handler.value,
        final CRDTFugueRichTextHandler handler => handler.text,
        _ => throw StateError('not a text handler'),
      };

  @override
  int get length => RuneOffsets.length(text);

  @override
  void insert(int index, String text) => switch (raw) {
        final CRDTTextHandler handler => handler.insert(index, text),
        final CRDTFugueTextHandler handler => handler.insert(index, text),
        final CRDTFugueRichTextHandler handler => handler.insert(index, text),
        _ => throw StateError('not a text handler'),
      };

  @override
  void delete(int index, int count) => switch (raw) {
        final CRDTTextHandler handler => handler.delete(index, count),
        final CRDTFugueTextHandler handler => handler.delete(index, count),
        final CRDTFugueRichTextHandler handler => handler.delete(index, count),
        _ => throw StateError('not a text handler'),
      };

  @override
  void insertEmbed(int index, Map<String, Object?> embed) =>
      (raw as CRDTFugueRichTextHandler).insertEmbed(index, embed);

  @override
  void updateEmbed(int index, Map<String, Object?> embed) =>
      (raw as CRDTFugueRichTextHandler).updateEmbed(index, embed);

  @override
  FugueElementID stablePositionAt(int index) => switch (raw) {
        final CRDTFugueTextHandler handler => handler.stablePositionAt(index),
        final CRDTFugueRichTextHandler handler =>
          handler.stablePositionAt(index),
        _ => throw StateError('not a Fugue handler'),
      };

  @override
  int? indexOfStablePosition(FugueElementID position) => switch (raw) {
        final CRDTFugueTextHandler handler =>
          handler.indexOfStablePosition(position),
        final CRDTFugueRichTextHandler handler =>
          handler.indexOfStablePosition(position),
        _ => throw StateError('not a Fugue handler'),
      };
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
  });

  /// Registers the handler under test.
  final Handler<dynamic> Function(CRDTDocument document, String id) makeHandler;

  /// Builds the field; it must call `onController` with its controller each
  /// time it builds, and publish its anchors to `onAnchors`.
  final Widget Function(
    String id,
    WidgetBuilder? deletedBuilder,
    void Function(TextEditingController controller) onController,
    SelectionAnchorsListener? onAnchors,
  ) buildField;

  late TextEditingController _controller;

  @override
  bool get supportsComposition => true;

  @override
  final bool supportsEmbeds;

  @override
  final bool supportsAnchors;

  @override
  ConformanceHandler createHandler(CRDTDocument document, String id) =>
      TextHandlerAccess(makeHandler(document, id));

  @override
  Widget build(
    CRDTDocument document,
    String id, {
    VoidCallback? onBuild,
    WidgetBuilder? deletedBuilder,
    SelectionAnchorsListener? onSelectionAnchorsChanged,
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
  Future<void> focus(WidgetTester tester) =>
      tester.showKeyboard(find.byType(TextField));

  @override
  Future<void> ime(WidgetTester tester, TextEditingValue value) async {
    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.updateEditingValue(value);
    await tester.pump();
  }
}
