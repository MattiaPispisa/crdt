// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Receives the stable anchors of the selection an editor publishes.
typedef SelectionAnchorsListener = void Function(
  FugueElementID? base,
  FugueElementID? extent,
);

/// A text handler seen by the suite, whatever its type.
///
/// Indexes count runes, like the handlers do.
abstract interface class ConformanceHandler {
  /// The handler itself, to delete it from the document.
  Handler<dynamic> get raw;

  /// The plain text.
  String get text;

  /// The number of runes of [text].
  int get length;

  /// Inserts [text] at the rune [index].
  void insert(int index, String text);

  /// Deletes [count] runes from the rune [index].
  void delete(int index, int count);

  /// Inserts the embed [embed] at the rune [index].
  void insertEmbed(int index, Map<String, Object?> embed);

  /// Replaces the data of the embed at the rune [index] with [embed].
  void updateEmbed(int index, Map<String, Object?> embed);

  /// The data of the embed at the rune [index]; `null` for text.
  ///
  /// Only called when `EditorHarness.supportsEmbeds` is `true`.
  Map<String, Object?>? embedAt(int index);

  /// Sets [key] to [value] on [count] runes from the rune [index].
  ///
  /// Only called when `EditorHarness.supportsFormat` is `true`.
  void format(int index, int count, String key, Object? value);

  /// The attributes of the rune [index].
  ///
  /// Only called when `EditorHarness.supportsFormat` is `true`.
  Map<String, Object?> attributesAt(int index);

  /// The changes of the handler, as they are published.
  Stream<Object?> watch();

  /// The anchor of a caret at the rune [index].
  ///
  /// Only called when `EditorHarness.supportsAnchors` is `true`.
  FugueElementID stablePositionAt(int index);

  /// The rune index [position] resolves to.
  ///
  /// Only called when `EditorHarness.supportsAnchors` is `true`.
  int? indexOfStablePosition(FugueElementID position);
}

/// What an editor binding gives the suite.
///
/// Write one harness per editor binding and pass a factory to
/// `runEditorConformanceTests`. The suite creates one harness per test, and
/// two for the tests with two peers.
///
/// Offsets and selections count UTF-16 code units of [editorText].
abstract class EditorHarness {
  /// Whether the editor takes IME input with a composing range.
  ///
  /// When `false`, `ime` is never called.
  bool get supportsComposition;

  /// Whether the editor shows embeds.
  ///
  /// When `false`, `insertEmbed` and `updateEmbed` are never called.
  bool get supportsEmbeds;

  /// Whether the editor publishes the stable anchors of its selection.
  ///
  /// When `false`, `focus` is never called.
  bool get supportsAnchors;

  /// Whether the editor undoes through a [CRDTUndoManager].
  ///
  /// When `false`, `build` gets no manager and `undo` is never called.
  bool get supportsUndo;

  /// Whether the editor formats a range.
  ///
  /// When `false`, `format` is never called.
  bool get supportsFormat;

  /// The origin of the writes of the editor, the one a [CRDTUndoManager]
  /// tracks.
  ///
  /// Only read when [supportsUndo] is `true`.
  Object get origin;

  /// Creates the text handler [id] on [document].
  ConformanceHandler createHandler(CRDTDocument document, String id);

  /// The editor bound to the handler [id] of [document], with its provider.
  ///
  /// [onBuild] runs each time the editor widget is built.
  /// [deletedBuilder] shows once the handler is deleted.
  /// [onSelectionAnchorsChanged] receives the anchors the editor publishes.
  /// [undoManager] undoes and redoes for the editor.
  Widget build(
    CRDTDocument document,
    String id, {
    VoidCallback? onBuild,
    WidgetBuilder? deletedBuilder,
    SelectionAnchorsListener? onSelectionAnchorsChanged,
    CRDTUndoManager? undoManager,
  });

  /// The plain text the user sees.
  String get editorText;

  /// The selection of the editor.
  TextSelection get selection;
  set selection(TextSelection value);

  /// Replaces `[start, end)` of [editorText] with [text], the way a keystroke
  /// or a paste does, with the caret after the new text.
  void replaceText(int start, int end, String text);

  /// Sets [key] to [value] on `[start, end)` of [editorText], the way a
  /// toolbar button does.
  void format(int start, int end, String key, Object? value);

  /// Undoes the last step, the way the editor's undo key does.
  void undo();

  /// Redoes the last undone step.
  void redo();

  /// Gives the editor the focus.
  Future<void> focus(WidgetTester tester);

  /// Hands [value] to the editor the way the platform keyboard does.
  Future<void> ime(WidgetTester tester, TextEditingValue value);
}
