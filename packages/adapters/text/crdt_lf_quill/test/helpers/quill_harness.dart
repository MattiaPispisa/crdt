// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/crdt_lf_quill.dart';
import 'package:editor_conformance/editor_conformance.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

class _RichHandler implements ConformanceHandler {
  _RichHandler(this._handler);

  final CRDTFugueRichTextHandler _handler;

  @override
  Handler<dynamic> get raw => _handler;

  @override
  String get text => _handler.text;

  @override
  int get length => _handler.length;

  @override
  void insert(int index, String text) => _handler.insert(index, text);

  @override
  void delete(int index, int count) => _handler.delete(index, count);
}

/// The editor suite harness of a `QuillController` bound by
/// `CrdtQuillBinder`.
///
/// No editor widget is mounted: the controller is the editor. Quill takes
/// platform input inside its own widgets, so the harness has no IME.
class QuillHarness extends EditorHarness {
  final QuillController _controller = QuillController.basic();

  @override
  bool get supportsComposition => false;

  @override
  ConformanceHandler createHandler(CRDTDocument document, String id) =>
      _RichHandler(CRDTFugueRichTextHandler(document, id));

  @override
  Widget build(
    CRDTDocument document,
    String id, {
    VoidCallback? onBuild,
    WidgetBuilder? deletedBuilder,
  }) {
    return CrdtProvider.value(
      value: document,
      child: CrdtQuillBinder(
        id: id,
        controller: _controller,
        deletedBuilder: deletedBuilder,
        builder: (context) {
          onBuild?.call();
          return const SizedBox();
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
  Future<void> ime(WidgetTester tester, TextEditingValue value) =>
      throw UnsupportedError('Quill takes platform input inside its widgets');
}
