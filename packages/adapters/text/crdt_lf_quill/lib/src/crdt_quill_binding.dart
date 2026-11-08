// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// Both packages export a `ChangeSource`: this file means Quill's.
import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource, Operation;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/src/quill_attributes.dart';
import 'package:crdt_lf_quill/src/quill_converters.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show TextSelection, WidgetsBinding;
import 'package:flutter_quill/flutter_quill.dart';

/// Whether the projection check compares the whole editor with the handler.
///
/// After each local write and remote change, the binder compares the lengths
/// of the editor and the handler and reads the handler again on a mismatch.
/// A drift that keeps the length is invisible to that. While `true`, a debug
/// build also compares the full content, attributes included, and throws on a
/// mismatch. That costs time linear in the document length on every change.
bool debugVerifyCrdtQuillProjection = true;

/// The origin of every write the Quill binding makes to the handler.
///
/// Pass it in `trackedOrigins` to make a `CRDTUndoManager` record the edits
/// made in the editor and nothing else.
const Object crdtQuillOrigin = Object();

/// Keeps a `QuillController` in step with a [CRDTFugueRichTextHandler] read
/// through [binding].
///
/// Call [bind], and pass [onReset], [onRemoteDelta] and [verifyProjection] to
/// the editor binding.
class CrdtQuillBinding {
  /// Creates a binding of [controller]; [bind] makes it take the edits.
  CrdtQuillBinding(
    QuillController controller, {
    this.onUnsupported,
    this.embedTypes,
    this._undoManager,
    this.onSelectionAnchorsChanged,
  }) : _controller = controller;

  QuillController _controller;

  /// Called with each embed the controller inserts that [embedTypes] or the
  /// handler refuses (see [CRDTFugueRichTextHandler.checkEmbed]), and with
  /// `{key: value}` for each attribute value the handler refuses (see
  /// [CRDTFugueRichTextHandler.checkAttribute]).
  void Function(Object? data)? onUnsupported;

  /// The types of the Quill embeds the editor writes to the handler; `null`
  /// takes all.
  Set<String>? embedTypes;

  /// Called with the anchors the editor publishes.
  void Function(FugueElementID? base, FugueElementID? extent)?
  onSelectionAnchorsChanged;

  /// The stable anchors of the selection.
  late final SelectionAnchors anchors = SelectionAnchors(
    (base, extent) => onSelectionAnchorsChanged?.call(base, extent),
  );

  ReplaceTextCallback? _userOnReplaceText;

  /// The manager that undoes and redoes; `null` keeps Quill's own history.
  CRDTUndoManager? get undoManager => _undoManager;

  /// A new manager drops the steps of Quill's history.
  set undoManager(CRDTUndoManager? value) {
    if (identical(value, _undoManager)) {
      return;
    }
    _undoManager = value;
    // A step recorded while the other stack ran no longer fits the document.
    _document?.history
      ?..clear()
      ..ignoreChange = value != null;
  }

  CRDTUndoManager? _undoManager;

  /// The editor binding that reads and writes the handler; `null` when the
  /// binding is not wired yet.
  CrdtEditorBinding<List<RichTextSpan>, RichTextDelta>? binding;

  bool _resetPending = false;
  bool _resetScheduled = false;

  /// The bound controller.
  ///
  /// A new controller takes the handler content at once, or at the end of
  /// the frame during a build. The old one keeps its document, unbound.
  QuillController get controller => _controller;

  set controller(QuillController value) {
    if (identical(value, _controller)) {
      return;
    }
    _release();
    _unhook();
    _controller = value;
    bind();
    final binding = this.binding;
    // A pending reset installs the document itself, at the end of the frame.
    if (binding != null && binding.isAttached && !_resetPending) {
      onReset(binding.readSynced(), ResetCause.initial);
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
  ///
  /// During a build, the handler is read again at the end of the frame.
  void onRemoteDelta(HandlerDelta<RichTextDelta> event) {
    // The base of the delta is stale: the pending reset reads it in.
    if (_resetPending) {
      return;
    }
    if (_inBuild()) {
      _deferReset(ResetCause.deltasMissed);
      return;
    }
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
    final content = document.toDelta();
    final stored = trailingNewline(content).stored;
    final runes = RuneOffsets.length(document.toPlainText()) - (stored ? 0 : 1);
    if (runes != handler.length) {
      return false;
    }
    assert(
      !debugVerifyCrdtQuillProjection ||
          _normalized(content) ==
              _normalized(quillDocumentFromSpans(handler.value)),
      'the editor drifted from the handler',
    );
    return true;
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
    // A bound document keeps its selection and its undo stack through the
    // reset. Those of another handler do not apply to the new content.
    if (cause == ResetCause.initial) {
      _release();
    }
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

  /// Wraps the `onReplaceText` of the controller and follows its selection,
  /// until [dispose].
  void bind() {
    _userOnReplaceText = _controller.onReplaceText;
    _controller
      ..onReplaceText = _onReplaceText
      ..addListener(captureAnchors);
  }

  void _unhook() {
    _controller.removeListener(captureAnchors);
    if (_controller.onReplaceText == _onReplaceText) {
      _controller.onReplaceText = _userOnReplaceText;
    }
    _userOnReplaceText = null;
  }

  // A refused embed, a refused attribute value and a typed U+FFFC are taken
  // out, and the rest of the edit is made again without them, on whole runes.
  bool _onReplaceText(int index, int len, Object? data) {
    final document = _document;
    if (document != null) {
      final plain = document.toPlainText();
      final (at, count, snapped) = _snappedToRunes(plain, index, len, data);
      final kept = _accepted(snapped);
      if (at != index || count != len || !identical(kept, data)) {
        final length = switch (kept) {
          final String text => text.length,
          final Delta delta => _insertedLength(delta),
          _ => 1,
        };
        final keepsEmbeds = _refusesEmbed(snapped);
        if (keepsEmbeds && length == 0) {
          return false;
        }
        if (count > 0 || length > 0) {
          _controller
            ..replaceText(
              at,
              keepsEmbeds ? 0 : count,
              keepsEmbeds
                  ? (kept! as Delta).deleteAroundEmbeds(plain, at, count)
                  : kept,
              null,
            )
            ..updateSelection(
              TextSelection.collapsed(offset: at + length),
              ChangeSource.local,
            );
        }
        return false;
      }
    }
    return _userOnReplaceText?.call(index, len, data) ?? true;
  }

  Object? _accepted(Object? data) => switch (data) {
    Embeddable() when _refusedEmbed(data) => _refuse(data, ''),
    final String text when text.contains(RichTextSpan.objectReplacement) =>
      text.replaceAll(RichTextSpan.objectReplacement, ''),
    final Delta delta => _acceptedDelta(delta),
    _ => data,
  };

  bool _refusesEmbed(Object? data) => switch (data) {
    Embeddable() => _refusedEmbed(data),
    final Delta delta => delta.toList().any(
      (op) => op.isInsert && op.data is! String && _refusedEmbed(op.data!),
    ),
    _ => false,
  };

  bool _accepts(Iterable<String> types) {
    final accepted = embedTypes;
    return accepted == null || types.every(accepted.contains);
  }

  bool _refusedEmbed(Object data) => switch (data) {
    Embeddable() =>
      !_accepts(_embedTypes({data.type: data.data})) || !_fits(data),
    final Map<dynamic, dynamic> map =>
      !_accepts(_embedTypes(map)) || !_fits(map),
    _ => false,
  };

  bool _refused(Operation op) {
    final data = op.data;
    return _refusesValue(op.attributes) ||
        op.isInsert &&
            switch (data) {
              final String text => text.contains(
                RichTextSpan.objectReplacement,
              ),
              _ => data != null && _refusedEmbed(data),
            };
  }

  bool _refusesValue(Map<String, dynamic>? attributes) =>
      attributes != null && !attributes.values.every(_fitsValue);

  bool _fitsValue(Object? value) =>
      _handlerTakes((handler) => handler.checkAttribute(value));

  // Whether the handler takes the data of the Quill embed [data].
  bool _fits(Object data) =>
      _handlerTakes((handler) => handler.checkEmbed(richTextEmbed(data)));

  bool _handlerTakes(void Function(CRDTFugueRichTextHandler handler) check) {
    final binding = this.binding;
    if (binding == null || !binding.isAttached) {
      return true;
    }
    try {
      check(_handler);
      return true;
      // The handler refuses data with an ArgumentError.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return false;
    }
  }

  Object? _refuse(Object? data, Object? kept) {
    onUnsupported?.call(data);
    return kept;
  }

  Map<String, dynamic>? _acceptedAttributes(Map<String, dynamic>? attributes) {
    if (attributes == null) {
      return null;
    }
    final kept = <String, dynamic>{};
    for (final MapEntry(:key, :value) in attributes.entries) {
      if (_fitsValue(value)) {
        kept[key] = value;
      } else {
        onUnsupported?.call({key: value});
      }
    }
    return kept.isEmpty ? null : kept;
  }

  // [delta] without what is refused. With [before], the plain text it applies
  // to, a run of inserts and deletes is one replace: see the README, "Embeds".
  Delta _acceptedDelta(Delta delta, {String? before}) {
    final ops = delta.toList();
    if (!ops.any(_refused)) {
      return delta;
    }
    final kept = Delta();
    var unit = 0;
    var o = 0;
    while (o < ops.length) {
      if (ops[o].isRetain) {
        final length = ops[o].length ?? 0;
        kept.retain(length, _acceptedAttributes(ops[o].attributes));
        unit += length;
        o++;
        continue;
      }
      var deleted = 0;
      var written = false;
      var refusedEmbed = false;
      for (; o < ops.length && !ops[o].isRetain; o++) {
        final op = ops[o];
        final data = op.data;
        if (op.isDelete) {
          deleted += op.length ?? 0;
        } else if (data is String) {
          final text = data.replaceAll(RichTextSpan.objectReplacement, '');
          kept.insert(text, _acceptedAttributes(op.attributes));
          written = written || text.isNotEmpty;
        } else if (data != null && _refusedEmbed(data)) {
          onUnsupported?.call(data);
          refusedEmbed = true;
        } else {
          kept.insert(data, _acceptedAttributes(op.attributes));
          written = true;
        }
      }
      if (before == null || !refusedEmbed) {
        kept.delete(deleted);
      } else if (written) {
        kept.deleteAroundEmbeds(before, unit, deleted);
      } else {
        kept.retain(deleted);
      }
      unit += deleted;
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
    final accepted = _acceptedDelta(change, before: before);
    final rich = richTextDeltaFromQuill(accepted, before, document: content);
    final written = RichTextEcho(quillRichTextWriter)..add(rich);
    binding.push(
      () => crdt.runInTransaction(() {
        final handler = _handler;
        quillRichTextWriter.write(handler, rich);
        final last = _syncLastNewline(
          document,
          handler,
          storedBefore: storedBefore,
        );
        if (last != null) {
          written.add(last);
        }
      }, origin: crdtQuillOrigin),
      // The editor already shows what was refused: read the handler back.
      isEcho: identical(accepted, change) ? written.echoes : (_) => false,
      ownStep: _isFormat(change) ? undoManager : null,
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
      quillRichTextWriter.write(handler, write);
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

  /// Anchors the selection of the controller.
  ///
  /// Only when the editor and the handler agree: an offset of a stale editor
  /// names the wrong element.
  void captureAnchors() {
    final binding = this.binding;
    final document = _document;
    if (onSelectionAnchorsChanged == null ||
        binding == null ||
        document == null ||
        _resetPending ||
        !binding.isAttached ||
        binding.isBehind) {
      return;
    }
    anchors.capture(
      _controller.selection,
      document.toPlainText(),
      _handler.stablePositionAt,
    );
  }

  void _install(Delta content) {
    _release();
    _withoutFocusRequest(
      () => _controller.document = _BoundDocument(content, this),
    );
  }

  void _release() {
    final document = _document;
    if (document != null) {
      document.owner = null;
      document.history.ignoreChange = false;
    }
  }

  void _compose(Delta delta, ChangeSource source) {
    delta.trim();
    if (delta.isEmpty) {
      return;
    }
    _withoutFocusRequest(
      () => _controller.compose(delta, _controller.selection, source),
    );
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

  CRDTUndoManager? get _manager => owner?.undoManager;

  // What the undo manager wrote back, as the editor received it.
  Delta? _replayed;

  @override
  bool get hasUndo => _manager?.canUndo ?? super.hasUndo;

  @override
  bool get hasRedo => _manager?.canRedo ?? super.hasRedo;

  // With a manager, the step moves the caret itself, and Quill's empty
  // history gives the "no change" result.
  @override
  // The inherited return type is not exported.
  // ignore: always_declare_return_types, type_annotate_public_apis
  undo() {
    final manager = _manager;
    if (manager != null) {
      _replay(manager.canUndo, manager.undo);
      history.clear();
    }
    return super.undo();
  }

  @override
  // The inherited return type is not exported.
  // ignore: always_declare_return_types, type_annotate_public_apis
  redo() {
    final manager = _manager;
    if (manager != null) {
      _replay(manager.canRedo, manager.redo);
      history.clear();
    }
    return super.redo();
  }

  void _replay(bool can, void Function() step) {
    final controller = owner?.controller;
    if (!can || controller == null) {
      return;
    }
    _replayed = Delta();
    step();
    final replayed = _replayed!;
    _replayed = null;
    if (replayed.isEmpty) {
      return;
    }
    // Caret like Quill's History: after the last insert or retain.
    var len = 0;
    for (final op in replayed.toList()) {
      if (op.isInsert || op.isRetain) {
        len += op.length ?? 0;
      }
    }
    controller.updateSelection(
      TextSelection.collapsed(offset: len),
      ChangeSource.local,
    );
  }

  // Quill adds a newline after each video it composes. Taken out here, the
  // selection and the undo stack move by [delta] alone.
  void _composeExactly(Delta delta, ChangeSource changeSource) {
    final before = _insertsVideo(delta) ? toDelta() : null;
    super.compose(delta, changeSource);
    if (before != null) {
      final extra = toDelta().diff(before.compose(delta));
      if (extra.isNotEmpty) {
        super.compose(extra, changeSource);
      }
    }
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
        _composeExactly(delta, changeSource);
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
    super.compose(delta, changeSource);
    // Quill adds a newline after each video it composes: write it too.
    final composed = _insertsVideo(delta)
        ? delta.compose(content.compose(delta).diff(toDelta()))
        : delta;
    owner._pushLocal(
      this,
      composed,
      before,
      content,
      storedBefore: storedBefore,
    );
  }
}

// [document] with each embed and attributes as the handler data they stand
// for.
Delta _normalized(Delta document) {
  final result = Delta();
  for (final op in document.toList()) {
    final data = op.data;
    result.insert(
      data is String ? data : richTextEmbed(data),
      _handlerAttributes(op.attributes),
    );
  }
  return result;
}

Map<String, dynamic>? _handlerAttributes(Map<String, dynamic>? attributes) {
  if (attributes == null) {
    return null;
  }
  final result = {
    for (final entry in richTextAttributes(attributes).entries)
      if (entry.value != null) entry.key: entry.value,
  };
  return result.isEmpty ? null : result;
}

// The types of the Quill embed [map]: its key, or the type of the map a
// wrapped embed holds.
Iterable<String> _embedTypes(Map<dynamic, dynamic> map) {
  final wrapped = map.length == 1 ? map[crdtQuillEmbedType] : null;
  final type = wrapped is Map ? wrapped[richTextEmbedTypeKey] : null;
  return type is String ? [type] : map.keys.map((key) => '$key');
}

int _insertedLength(Delta delta) => delta
    .toList()
    .where((op) => op.isInsert)
    .fold(0, (sum, op) => sum + (op.length ?? 0));

// Quill's diff of the input cuts at the first code unit that differs, so a
// half left out of the range joins [data] when the two make a pair.
(int, int, Object?) _snappedToRunes(
  String plain,
  int index,
  int len,
  Object? data,
) {
  final end = index + len;
  final splitsStart = RuneOffsets.splitsPair(plain, index);
  final splitsEnd = RuneOffsets.splitsPair(plain, end);
  if (!splitsStart && !splitsEnd) {
    return (index, len, data);
  }
  if (len == 0) {
    return (index - 1, 0, data);
  }
  var joined = data;
  if (joined is String && splitsStart && joined.isNotEmpty) {
    if (RuneOffsets.isLowSurrogate(joined.codeUnitAt(0))) {
      joined = '${plain[index - 1]}$joined';
    }
  }
  if (joined is String && splitsEnd && joined.isNotEmpty) {
    if (RuneOffsets.isHighSurrogate(joined.codeUnitAt(joined.length - 1))) {
      joined = '$joined${plain[end]}';
    }
  }
  final from = splitsStart ? index - 1 : index;
  return (from, (splitsEnd ? end + 1 : end) - from, joined);
}

extension on Delta {
  // Deletes the [count] code units from [from] of [plain], but its embeds.
  Delta deleteAroundEmbeds(String plain, int from, int count) {
    for (var unit = from; unit < from + count; unit++) {
      if (isEmbedAt(plain, unit)) {
        retain(1);
      } else {
        delete(1);
      }
    }
    return this;
  }
}

bool _isFormat(Delta delta) {
  final ops = delta.toList();
  return ops.every((op) => op.isRetain) &&
      ops.any((op) => op.attributes != null);
}

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
