// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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

  /// Creates the text handler [id] on [document].
  ConformanceHandler createHandler(CRDTDocument document, String id);

  /// The editor bound to the handler [id] of [document], with its provider.
  ///
  /// [onBuild] runs each time the editor widget is built.
  /// [deletedBuilder] shows once the handler is deleted.
  Widget build(
    CRDTDocument document,
    String id, {
    VoidCallback? onBuild,
    WidgetBuilder? deletedBuilder,
  });

  /// The plain text the user sees.
  String get editorText;

  /// The selection of the editor.
  TextSelection get selection;
  set selection(TextSelection value);

  /// Replaces `[start, end)` of [editorText] with [text], the way a keystroke
  /// or a paste does, with the caret after the new text.
  void replaceText(int start, int end, String text);

  /// Hands [value] to the editor the way the platform keyboard does.
  Future<void> ime(WidgetTester tester, TextEditingValue value);
}
