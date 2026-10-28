// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// Both packages export a `ChangeSource`: this file means Quill's.
import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/src/quill_attributes.dart';
import 'package:crdt_lf_quill/src/quill_converters.dart';
import 'package:crdt_lf_quill/src/rich_text_writer.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_quill/flutter_quill.dart';

/// Whether the projection check compares the whole editor with the handler.
///
/// After each local write and remote change, the binder checks the editor
/// against the handler and reads the handler again on a mismatch. The check
/// always compares the lengths. When `true` (the default), it also compares
/// the full content, attributes included. Despite the name, the switch also
/// works in release builds. The full compare adds time linear in the
/// document length to every change: set it to `false` to skip it.
bool debugVerifyCrdtQuillProjection = true;

/// Keeps a `QuillController` in step with a [CRDTFugueRichTextHandler] read
/// through [binding].
///
/// Pass [onReset], [onRemoteDelta] and [verifyProjection] to the editor
/// binding.
class CrdtQuillBinding {
  /// Creates a binding that wraps the `onReplaceText` of [controller].
  CrdtQuillBinding(QuillController controller, {this.onUnsupported})
    : _controller = controller {
    _hook();
  }

  QuillController _controller;

  /// Called with the refused data when the controller inserts an embed.
  void Function(Object? data)? onUnsupported;

  ReplaceTextCallback? _userOnReplaceText;

  /// The editor binding that reads and writes the handler; `null` when the
  /// binding is not wired yet.
  CrdtEditorBinding<List<RichTextSpan>, RichTextDelta>? binding;

  bool _resetPending = false;
  bool _resetScheduled = false;

  /// The bound controller.
  ///
  /// A new controller takes the handler content at once, unless a reset is
  /// pending. The old one keeps its document, unbound.
  QuillController get controller => _controller;

  set controller(QuillController value) {
    if (identical(value, _controller)) {
      return;
    }
    _release();
    _unhook();
    _controller = value;
    _hook();
    final binding = this.binding;
    // A pending reset installs the document itself, at the end of the frame.
    if (binding != null && binding.isAttached && !_resetPending) {
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

  /// Shows [spans] in the editor, the whole handler value.
  ///
  /// A bound document gets the difference as a silent change, so the
  /// selection stays. Otherwise the controller gets a new document. During a
  /// build, the reset is put off to the end of the frame.
  void onReset(List<RichTextSpan> spans, ResetCause cause) {
    if (_inBuild()) {
      _deferReset(cause);
      return;
    }
    _resetPending = false;
    final target = quillDocumentFromSpans(spans);
    final document = _document;
    if (document == null) {
      _install(target);
      return;
    }
    _compose(document.toDelta().diff(target), ChangeSource.silent);
  }

  /// Applies a change from the handler to the editor as
  /// [ChangeSource.remote].
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

  /// Whether the editor shows the handler value.
  ///
  /// See [debugVerifyCrdtQuillProjection] for what is compared.
  bool verifyProjection() {
    // The editor is stale until the pending reset, which reads the handler.
    if (_resetPending) {
      return true;
    }
    final document = _document;
    if (document == null) {
      return false;
    }
    final handler = _handler;
    final stored = trailingNewline(document.toDelta()).stored;
    final runes = RuneOffsets.length(document.toPlainText()) - (stored ? 0 : 1);
    if (runes != handler.length) {
      return false;
    }
    return !debugVerifyCrdtQuillProjection ||
        document.toDelta() == quillDocumentFromSpans(handler.value);
  }

  /// Stops writing to the handler and gives back the `onReplaceText` of the
  /// controller.
  void dispose() {
    _release();
    _unhook();
    _resetPending = false;
    binding = null;
  }

  // A reset in build would notify the controller's listeners, and one of
  // them may be a widget built earlier in this frame.
  void _deferReset(ResetCause cause) {
    // The reset reads the handler again: a delta applied before it would
    // count twice.
    _release();
    _resetPending = true;
    if (_resetScheduled) {
      return;
    }
    _resetScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _resetScheduled = false;
        if (_resetPending) {
          // Read now: the handler may have moved since the build.
          binding?.resync(cause);
        }
      })
      ..ensureVisualUpdate();
  }

  void _hook() {
    _userOnReplaceText = _controller.onReplaceText;
    _controller.onReplaceText = _onReplaceText;
  }

  void _unhook() {
    if (_controller.onReplaceText == _onReplaceText) {
      _controller.onReplaceText = _userOnReplaceText;
    }
    _userOnReplaceText = null;
  }

  bool _onReplaceText(int index, int len, Object? data) {
    if (_document != null && _hasEmbed(data)) {
      onUnsupported?.call(data);
      return false;
    }
    return _userOnReplaceText?.call(index, len, data) ?? true;
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
    final rich = richTextDeltaFromQuill(_withoutEmbeds(change), before);
    binding.push(
      () => crdt.runInTransaction(() {
        final handler = _handler;
        writeRichTextDelta(handler, rich);
        _syncLastNewline(document, handler, storedBefore: storedBefore);
      }),
    );
  }

  // The handler stores Quill's last newline only while one of the newlines
  // that end the text has a block attribute: add or drop it on a flip.
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

// Overrides `compose` instead of listening to `changes`: that stream is
// asynchronous, so a remote delta could arrive on a wrong base.
class _BoundDocument extends Document {
  _BoundDocument(super.delta, this.owner) : super.fromDelta();

  CrdtQuillBinding? owner;

  @override
  void compose(Delta delta, ChangeSource changeSource) {
    if (changeSource != ChangeSource.local) {
      // What `History(userOnly: true)` does, by hand: `Document` builds its
      // own `History`. A peer change moves the undo stack and never enters it.
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

bool _hasEmbed(Object? data) => switch (data) {
  Embeddable() => true,
  Delta() => data.toList().any((op) => op.isInsert && op.data is! String),
  _ => false,
};

// An embed composed past `onReplaceText` stays in the editor until the
// projection check reads the handler again. The converters throw on embeds.
Delta _withoutEmbeds(Delta change) {
  final ops = change.toList();
  if (!ops.any((op) => op.isInsert && op.data is! String)) {
    return change;
  }
  return Delta.fromOperations([
    for (final op in ops)
      if (!op.isInsert || op.data is String) op,
  ]);
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

bool _inBuild() {
  if (kDebugMode) {
    // Plain unit tests run without a binding.
    if (BindingBase.debugBindingType() == null) {
      return false;
    }
    // The first build of a root widget runs outside a frame.
    if (WidgetsBinding.instance.buildOwner?.debugBuilding ?? false) {
      return true;
    }
  }
  return SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks;
}
