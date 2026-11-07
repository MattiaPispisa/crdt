// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/crdt_lf_quill.dart';
import 'package:editor_conformance/editor_conformance.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

/// The editor suite harness of a `QuillController` bound by
/// `CrdtQuillBinder`.
///
/// No editor widget is mounted: the controller is the editor. Quill takes
/// platform input inside its own widgets, so the harness has no IME.
class QuillHarness extends EditorHarness {
  final QuillController _controller = QuillController.basic();
  final FocusNode _focus = FocusNode();

  @override
  bool get supportsComposition => false;

  @override
  bool get supportsEmbeds => true;

  @override
  bool get supportsAnchors => true;

  @override
  bool get supportsUndo => true;

  @override
  bool get supportsFormat => true;

  @override
  Object get origin => crdtQuillOrigin;

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
    return CrdtProvider.value(
      value: document,
      child: CrdtQuillBinder(
        id: id,
        controller: _controller,
        deletedBuilder: deletedBuilder,
        onSelectionAnchorsChanged: onSelectionAnchorsChanged,
        undoManager: undoManager,
        builder: (context) {
          onBuild?.call();
          return Focus(focusNode: _focus, child: const SizedBox());
        },
      ),
    );
  }

  // A Quill document always ends with a newline the user cannot delete.
  @override
  String get editorText {
    final text = _controller.document.toPlainText();
    return text.substring(0, text.length - 1);
  }

  @override
  TextSelection get selection => _controller.selection;

  @override
  set selection(TextSelection value) =>
      _controller.updateSelection(value, ChangeSource.local);

  @override
  void replaceText(int start, int end, String text) {
    _controller.replaceText(
      start,
      end - start,
      text,
      TextSelection.collapsed(offset: start + text.length),
    );
  }

  @override
  void format(int start, int end, String key, Object? value) => _controller
      .formatText(start, end - start, Attribute.fromKeyValue(key, value));

  @override
  void undo() => _controller.undo();

  @override
  void redo() => _controller.redo();

  @override
  Future<void> focus(WidgetTester tester) async {
    _focus.requestFocus();
    await tester.pump();
  }

  @override
  Future<void> ime(WidgetTester tester, TextEditingValue value) =>
      throw UnsupportedError('Quill takes platform input inside its widgets');
}
