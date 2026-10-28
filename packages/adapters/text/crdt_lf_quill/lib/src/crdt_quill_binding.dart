// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/src/quill_attributes.dart';
import 'package:crdt_lf_quill/src/quill_converters.dart';
import 'package:crdt_lf_quill/src/rich_text_writer.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter_quill/flutter_quill.dart';

bool debugVerifyCrdtQuillProjection = true;

class CrdtQuillBinding {
  CrdtQuillBinding(QuillController controller) : _controller = controller;

  QuillController _controller;

  CrdtEditorBinding<List<RichTextSpan>, RichTextDelta>? binding;

  QuillController get controller => _controller;

  set controller(QuillController value) {
    if (identical(value, _controller)) {
      return;
    }
    _release();
    _controller = value;
    final binding = this.binding;
    if (binding != null && binding.isAttached) {
      _install(quillDocumentFromSpans(_handler.value));
    }
  }

  CRDTFugueRichTextHandler get _handler =>
      binding!.provider as CRDTFugueRichTextHandler;

  _BoundDocument? get _document {
    final document = _controller.document;
    return document is _BoundDocument && document.owner == this
        ? document
        : null;
  }

  void onReset(List<RichTextSpan> spans, ResetCause cause) {
    final target = quillDocumentFromSpans(spans);
    final document = _document;
    if (document == null) {
      _install(target);
      return;
    }
    _compose(document.toDelta().diff(target), ChangeSource.silent);
  }

  void onRemoteDelta(HandlerDelta<RichTextDelta> event) {
    final document = _document;
    if (document == null) {
      return;
    }
    final delta = event.delta;
    final before = document.toPlainText();
    final tail = trailingNewline(document.toDelta());
    if (tail.stored) {
      final anchor = RuneOffsets.length(before) - 1 - tail.fromEnd;
      if (_staysBefore(delta, anchor)) {
        _compose(quillDeltaFromRichText(delta, before), ChangeSource.remote);
        return;
      }
      // The last newline is stored: add one in front of it that takes its
      // attributes, so the delta lands on the shape of a free last line.
      final last = _blockAttributes(document.toDelta(), 0);
      _compose(
        Delta()
          ..retain(document.length - 1)
          ..insert('\n', last.isEmpty ? null : last)
          ..retain(
            1,
            last.isEmpty ? null : {for (final key in last.keys) key: null},
          ),
        ChangeSource.remote,
      );
      _compose(quillDeltaFromRichText(delta, '$before\n'), ChangeSource.remote);
    } else {
      _compose(quillDeltaFromRichText(delta, before), ChangeSource.remote);
    }

    final after = document.toDelta();
    if (trailingNewline(after, skip: 1).stored) {
      // The handler now ends with a stored newline: it becomes the last one.
      final stored = _blockAttributes(after, 1);
      _compose(
        Delta()
          ..retain(document.length - 2)
          ..delete(1)
          ..retain(1, stored.isEmpty ? null : stored),
        ChangeSource.remote,
      );
    }
  }

  bool verifyProjection() {
    final document = _document;
    if (document == null) {
      return false;
    }
    final handler = _handler;
    final stored = trailingNewline(document.toDelta()).stored;
    final runes = RuneOffsets.length(document.toPlainText()) - (stored ? 0 : 1);
    assert(
      !debugVerifyCrdtQuillProjection ||
          document.toDelta() == quillDocumentFromSpans(handler.value),
      'the Quill document drifted from the handler',
    );
    return runes == handler.length;
  }

  void dispose() {
    _release();
    binding = null;
  }

  void _pushLocal(
    _BoundDocument document,
    Delta change,
    String before, {
    required bool storedBefore,
  }) {
    final binding = this.binding;
    final crdt = binding?.document;
    if (binding == null || crdt == null) {
      return;
    }
    final rich = richTextDeltaFromQuill(change, before);
    binding.push(
      () => crdt.runInTransaction(() {
        final handler = _handler;
        writeRichTextDelta(handler, rich);
        _syncLastNewline(document, handler, storedBefore: storedBefore);
      }),
    );
  }

  void _syncLastNewline(
    _BoundDocument document,
    CRDTFugueRichTextHandler handler, {
    required bool storedBefore,
  }) {
    final content = document.toDelta();
    final storedAfter = trailingNewline(content).stored;
    if (storedAfter == storedBefore) {
      return;
    }
    if (storedAfter) {
      writeRichTextDelta(
        handler,
        RichTextDelta([
          RichTextRetain(handler.length),
          RichTextInsert('\n', _blockAttributes(content, 0)),
        ]),
      );
      return;
    }
    if (handler.length > 0) {
      handler.delete(handler.length - 1, 1);
    }
  }

  void _install(Delta content) {
    _release();
    _controller.document = _BoundDocument(content, this);
  }

  void _release() {
    _document?.owner = null;
  }

  void _compose(Delta delta, ChangeSource source) {
    delta.trim();
    if (delta.isEmpty) {
      return;
    }
    _controller.compose(delta, _controller.selection, source);
  }
}

class _BoundDocument extends Document {
  _BoundDocument(super.delta, this.owner) : super.fromDelta();

  CrdtQuillBinding? owner;

  @override
  void compose(Delta delta, ChangeSource changeSource) {
    if (changeSource != ChangeSource.local) {
      // What `History(userOnly: true)` does: a change from a peer moves the
      // undo stack and never enters it.
      final history = this.history;
      final ignored = history.ignoreChange;
      history.ignoreChange = true;
      try {
        super.compose(delta, changeSource);
      } finally {
        history.ignoreChange = ignored;
      }
      if (!ignored) {
        history.transform(delta);
      }
      return;
    }
    final owner = this.owner;
    if (owner == null) {
      super.compose(delta, changeSource);
      return;
    }
    final before = toPlainText();
    final storedBefore = trailingNewline(toDelta()).stored;
    super.compose(delta, changeSource);
    owner._pushLocal(this, delta, before, storedBefore: storedBefore);
  }
}

// Every edit, insert included, is before [anchor]: the stored last newline
// keeps its place.
bool _staysBefore(RichTextDelta delta, int anchor) {
  var index = 0;
  for (final op in delta.ops) {
    switch (op) {
      case RichTextRetain():
        if (op.attributes.isNotEmpty && index + op.count > anchor) {
          return false;
        }
        index += op.count;
      case RichTextInsert():
        if (index > anchor) {
          return false;
        }
      case RichTextDelete():
        if (index + op.count > anchor) {
          return false;
        }
        index += op.count;
    }
  }
  return true;
}

Map<String, dynamic> _blockAttributes(Delta document, int fromEnd) {
  var index = 0;
  final ops = document.toList();
  for (var o = ops.length - 1; o >= 0; o--) {
    final op = ops[o];
    final length = op.length ?? 0;
    if (index + length > fromEnd) {
      return {
        for (final entry in (op.attributes ?? const {}).entries)
          if (entry.value != null && isQuillBlockKey(entry.key))
            entry.key: entry.value,
      };
    }
    index += length;
  }
  return const {};
}
