// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// Both packages export a `ChangeSource`: this file means Quill's.
import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource, Operation;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/src/quill_attributes.dart';
import 'package:crdt_lf_quill/src/quill_converters.dart';
import 'package:crdt_lf_quill/src/rich_text_writer.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show TextSelection, WidgetsBinding;
import 'package:flutter_quill/flutter_quill.dart';
// `History`, the type of `Document.history`, is not exported.
// ignore: implementation_imports
import 'package:flutter_quill/src/document/history.dart';
// `HistoryChanged`, the return type of `Document.undo`, is not exported.
// ignore: implementation_imports
import 'package:flutter_quill/src/document/structs/history_changed.dart';

/// Whether the projection check compares the whole editor with the handler.
///
/// After each local write and remote change, the binder checks the editor
/// against the handler and reads the handler again on a mismatch. The check
/// always compares the lengths. When `true` (the default), it also compares
/// the full content, attributes included. Despite the name, the switch also
/// works in release builds. The full compare adds time linear in the
/// document length to every change: set it to `false` to skip it.
bool debugVerifyCrdtQuillProjection = true;

/// The origin of every write the Quill binding makes to the handler.
///
/// Pass it in `trackedOrigins` to make a `CRDTUndoManager` record the edits
/// made in the editor and nothing else.
const Object crdtQuillOrigin = Object();

/// Keeps a `QuillController` in step with a [CRDTFugueRichTextHandler] read
/// through [binding].
///
/// Pass [onReset], [onRemoteDelta] and [verifyProjection] to the editor
/// binding.
class CrdtQuillBinding {
  /// Creates a binding that wraps the `onReplaceText` of [controller].
  CrdtQuillBinding(
    QuillController controller, {
    this.onUnsupported,
    this.embedTypes,
    CRDTUndoManager? undoManager,
  }) : _controller = controller {
    _undoManager = undoManager;
    _hook();
  }

  QuillController _controller;

  /// Called with each embed the controller inserts that [embedTypes]
  /// refuses.
  void Function(Object? data)? onUnsupported;

  /// The keys of the Quill embeds written to the handler; `null` takes all.
  Set<String>? embedTypes;

  ReplaceTextCallback? _userOnReplaceText;

  /// The manager that undoes and redoes; `null` keeps Quill's own history.
  CRDTUndoManager? get undoManager => _undoManager;

  set undoManager(CRDTUndoManager? value) {
    _undoManager = value;
    _document?.history.ignoreChange = value != null;
  }

  CRDTUndoManager? _undoManager;

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
    final content = document.toDelta();
    final tail = trailingNewline(content);
    if (tail.stored) {
      final anchor = RuneOffsets.length(before) - 1 - tail.fromEnd;
      if (_staysBefore(delta, anchor)) {
        _compose(
          quillDeltaFromRichText(delta, before, document: content),
          ChangeSource.remote,
        );
        return;
      }
      // The last newline is stored: add one in front of it that takes its
      // attributes, so the delta lands on the shape of a free last line.
      final last = _blockAttributes(content, 0);
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
      _compose(
        quillDeltaFromRichText(
          delta,
          '$before\n',
          document: document.toDelta(),
        ),
        ChangeSource.remote,
      );
    } else {
      _compose(
        quillDeltaFromRichText(delta, before, document: content),
        ChangeSource.remote,
      );
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
        _unwrapped(document.toDelta()) ==
            _unwrapped(quillDocumentFromSpans(handler.value));
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

  // A refused embed and a typed U+FFFC are taken out, and the rest of the
  // edit is made again without them.
  bool _onReplaceText(int index, int len, Object? data) {
    if (_document != null) {
      final kept = _accepted(data);
      if (!identical(kept, data)) {
        final length = switch (kept) {
          final String text => text.length,
          final Delta delta => _insertedLength(delta),
          _ => 1,
        };
        if (len > 0 || length > 0) {
          _controller
            ..replaceText(index, len, kept, null)
            ..updateSelection(
              TextSelection.collapsed(offset: index + length),
              ChangeSource.local,
            );
        }
        return false;
      }
    }
    return _userOnReplaceText?.call(index, len, data) ?? true;
  }

  Object? _accepted(Object? data) => switch (data) {
    Embeddable() when !_accepts([data.type]) => _refuse(data, ''),
    final String text when text.contains(RichTextSpan.objectReplacement) =>
      text.replaceAll(RichTextSpan.objectReplacement, ''),
    final Delta delta => _acceptedDelta(delta),
    _ => data,
  };

  bool _accepts(Iterable<String> types) {
    final accepted = embedTypes;
    return accepted == null || types.every(accepted.contains);
  }

  Object? _refuse(Object? data, Object? kept) {
    onUnsupported?.call(data);
    return kept;
  }

  Delta _acceptedDelta(Delta delta) {
    final ops = delta.toList();
    bool refused(Operation op) {
      final data = op.data;
      return op.isInsert &&
          switch (data) {
            final String text => text.contains(RichTextSpan.objectReplacement),
            Embeddable() => !_accepts([data.type]),
            final Map<dynamic, dynamic> map => !_accepts(map.keys.cast()),
            _ => false,
          };
    }

    if (!ops.any(refused)) {
      return delta;
    }
    final kept = Delta();
    for (final op in ops) {
      final data = op.data;
      if (!refused(op)) {
        kept.push(op);
      } else if (data is String) {
        kept.insert(
          data.replaceAll(RichTextSpan.objectReplacement, ''),
          op.attributes,
        );
      } else {
        onUnsupported?.call(data);
      }
    }
    return kept;
  }

  void _pushLocal(
    _BoundDocument document,
    Delta change,
    String before,
    Delta content, {
    required bool storedBefore,
  }) {
    final binding = this.binding;
    final crdt = binding?.document;
    if (binding == null || crdt == null) {
      return;
    }
    final rich = richTextDeltaFromQuill(
      _acceptedDelta(change),
      before,
      document: content,
    );
    final written = _Written()..add(rich);
    binding.push(
      () => crdt.runInTransaction(() {
        final handler = _handler;
        writeRichTextDelta(handler, rich);
        final last = _syncLastNewline(
          document,
          handler,
          storedBefore: storedBefore,
        );
        if (last != null) {
          written.add(last);
        }
      }, origin: crdtQuillOrigin),
      isEcho: written.echoes,
    );
  }

  // The handler stores Quill's last newline only while one of the newlines
  // that end the text has a block attribute: add or drop it on a flip.
  RichTextDelta? _syncLastNewline(
    _BoundDocument document,
    CRDTFugueRichTextHandler handler, {
    required bool storedBefore,
  }) {
    final content = document.toDelta();
    final storedAfter = trailingNewline(content).stored;
    if (storedAfter == storedBefore) {
      return null;
    }
    if (storedAfter) {
      final write = RichTextDelta([
        RichTextRetain(handler.length),
        RichTextInsert('\n', _blockAttributes(content, 0)),
      ]);
      writeRichTextDelta(handler, write);
      return write;
    }
    if (handler.length == 0) {
      return null;
    }
    handler.delete(handler.length - 1, 1);
    return RichTextDelta([
      RichTextRetain(handler.length),
      const RichTextDelete(1),
    ]);
  }

  void _install(Delta content) {
    _release();
    _withoutFocusRequest(
      () => _controller.document = _BoundDocument(content, this),
    );
  }

  void _release() {
    _document?.owner = null;
  }

  void _compose(Delta delta, ChangeSource source) {
    delta.trim();
    if (delta.isEmpty) {
      return;
    }
    // Quill adds a newline after each video it composes: take it out again.
    final before = _insertsVideo(delta) ? _controller.document.toDelta() : null;
    _withoutFocusRequest(
      () => _controller.compose(delta, _controller.selection, source),
    );
    if (before != null) {
      final extra = _controller.document.toDelta().diff(before.compose(delta));
      if (extra.isNotEmpty) {
        _withoutFocusRequest(
          () => _controller.compose(extra, _controller.selection, source),
        );
      }
    }
  }

  // On the web the editor asks for focus on every controller change. A peer's
  // change would take the focus from the editor the user types in.
  void _withoutFocusRequest(void Function() change) {
    _controller.skipRequestKeyboard = true;
    try {
      change();
    } finally {
      _controller.skipRequestKeyboard = false;
    }
  }
}

// Overrides `compose` instead of listening to `changes`: that stream is
// asynchronous, so a remote delta could arrive on a wrong base.
class _BoundDocument extends Document {
  _BoundDocument(super.delta, this.owner) : super.fromDelta() {
    // One stack only: Quill's History records nothing.
    if (owner?.undoManager != null) {
      history.ignoreChange = true;
    }
  }

  CrdtQuillBinding? owner;

  final _ComposedHistory _history = _ComposedHistory();

  @override
  _ComposedHistory get history => _history;

  CRDTUndoManager? get _manager => owner?.undoManager;

  // What the undo manager wrote back, as the editor received it.
  Delta? _replayed;

  @override
  bool get hasUndo => _manager?.canUndo ?? super.hasUndo;

  @override
  bool get hasRedo => _manager?.canRedo ?? super.hasRedo;

  @override
  HistoryChanged undo() {
    final manager = _manager;
    if (manager == null) {
      return super.undo();
    }
    return _replay(manager.canUndo, manager.undo);
  }

  @override
  HistoryChanged redo() {
    final manager = _manager;
    if (manager == null) {
      return super.redo();
    }
    return _replay(manager.canRedo, manager.redo);
  }

  HistoryChanged _replay(bool can, void Function() step) {
    if (!can) {
      return const HistoryChanged(false, 0);
    }
    _replayed = Delta();
    step();
    final replayed = _replayed!;
    _replayed = null;
    // Caret like Quill's History: after the last insert or retain.
    var len = 0;
    for (final op in replayed.toList()) {
      if (op.isInsert || op.isRetain) {
        len += op.length ?? 0;
      }
    }
    return HistoryChanged(true, len);
  }

  @override
  void compose(Delta delta, ChangeSource changeSource) {
    if (changeSource != ChangeSource.local) {
      final replayed = _replayed;
      if (replayed != null) {
        _replayed = replayed.compose(delta);
      }
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
    final content = toDelta();
    final storedBefore = trailingNewline(content).stored;
    _history.composed = null;
    super.compose(delta, changeSource);
    // What Quill composed, newlines it added after a video included.
    final composed = _history.composed ?? delta;
    owner._pushLocal(
      this,
      composed,
      before,
      content,
      storedBefore: storedBefore,
    );
  }
}

class _ComposedHistory extends History {
  Delta? composed;

  @override
  void handleDocChange(DocChange docChange) {
    composed = docChange.change;
    super.handleDocChange(docChange);
  }
}

// What one push writes, to tell its echo from a foreign change.
class _Written {
  int _inserted = 0;
  int _deleted = 0;
  int _embedsInserted = 0;
  int _embedsUpdated = 0;
  final List<OwnsFormat> _formats = [];

  void add(RichTextDelta delta) {
    var index = 0;
    void own(int count, Map<String, Object?> attributes) {
      if (attributes.isNotEmpty) {
        _formats.add(formatsWithin(index, index + count, attributes));
      }
      index += count;
    }

    // Inserted content gets exactly its attributes: the write first clears
    // what it takes from its left, then sets its keys.
    void put(int count, Map<String, Object?> attributes) {
      final from = index;
      final to = index += count;
      _formats.add(
        (start, end, written) =>
            start >= from &&
            end <= to &&
            written.entries.every(
              (entry) =>
                  entry.value == null || attributes[entry.key] == entry.value,
            ),
      );
    }

    for (final op in delta.ops) {
      switch (op) {
        case RichTextRetain():
          own(op.count, op.attributes);
        case RichTextInsert():
          _inserted += op.length;
          put(op.length, op.attributes);
        case RichTextInsertEmbed():
          _embedsInserted++;
          put(1, op.attributes);
        case RichTextUpdateEmbed():
          _embedsUpdated++;
          own(1, op.attributes);
        case RichTextDelete():
          _deleted += op.count;
      }
    }
  }

  bool echoes(List<RichTextDelta> dropped) => echoesRichText(
    dropped,
    deleted: _deleted,
    inserted: _inserted,
    embedsInserted: _embedsInserted,
    embedsUpdated: _embedsUpdated,
    ownsFormat: (from, to, attributes) =>
        _formats.any((owns) => owns(from, to, attributes)),
  );
}

// [document] with each embed as the handler map it stands for.
Delta _unwrapped(Delta document) => Delta.fromOperations([
  for (final op in document.toList())
    if (op.isInsert && op.data is! String)
      Operation.insert(richTextEmbed(op.data), op.attributes)
    else
      op,
]);

int _insertedLength(Delta delta) => delta
    .toList()
    .where((op) => op.isInsert)
    .fold(0, (sum, op) => sum + (op.length ?? 0));

bool _insertsVideo(Delta delta) => delta.toList().any(
  (op) =>
      op.isInsert &&
      op.data is Map &&
      (op.data! as Map).containsKey(BlockEmbed.videoType),
);

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
      case RichTextInsert() || RichTextInsertEmbed():
        if (index > anchor) {
          return false;
        }
      case RichTextUpdateEmbed():
        if (index + 1 > anchor) {
          return false;
        }
        index++;
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
