// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/common/_crdt_guards.dart';
import 'package:crdt_lf_flutter/src/effects/_text_field_core.dart';
import 'package:crdt_lf_flutter/src/effects/_text_field_engine.dart';
import 'package:crdt_lf_flutter/src/effects/text_delta.dart';
import 'package:crdt_lf_flutter/src/provider/_crdt_view.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_helper.dart';
import 'package:flutter/widgets.dart';

/// Whether [CrdtTextFieldBuilder] compares its whole text against the handler.
///
/// The field derives its text from the deltas instead of projecting the whole
/// document, and checks the result after every step — in release too, with a
/// question that costs nothing: the whole string for `CRDTTextHandler`, the
/// O(1) length for `CRDTFugueTextHandler`. A drift that keeps the length is the
/// one that cheap question cannot see.
///
/// While `true`, a debug build **also** compares the whole value and throws on
/// a mismatch, closing that gap. That comparison reads the value, which is the
/// cost the field exists to avoid, so only a benchmark should turn it off.
bool debugVerifyCrdtTextFieldProjection = true;

/// {@template crdt_text_field_builder}
/// Binds a [TextEditingController] to the text handler registered under [id]
/// (`CRDTTextHandler` or `CRDTFugueTextHandler`):
///
/// - **Local edits** are pushed into the handler immediately, as the precise
///   [TextDelta] of each editing gesture (common prefix/suffix trimming — no
///   full-text diff, no debounce). Multi-op gestures run in a single
///   transaction, so each gesture emits one document update.
/// - **IME composition** is respected: while a composing region is active
///   (CJK input, autocorrect) nothing is committed; the accumulated delta is
///   pushed when composition ends.
/// - **Remote changes** are adopted into the controller in place, with the
///   caret and selection kept visually anchored. With a
///   `CRDTFugueTextHandler` the anchor is a stable position
///   ([CRDTFugueTextHandler.stablePositionAt]) tied to the identity of the
///   element left of the caret. Without one, the offsets ride on the
///   `SequenceDelta` the handler reports, which says exactly what moved even
///   when a change touched several regions. Only a change no delta can
///   describe — a snapshot import, a dropped cache — falls back to a diff of
///   the two texts.
/// - The subtree **never rebuilds**: the widget listens to the document
///   directly and updates the controller, exactly like a headless editor
///   binding. [builder] runs once.
///
/// ## Example
/// ```dart
/// CrdtTextFieldBuilder(
///   id: 'note',
///   builder: (context, controller) => TextField(controller: controller),
/// ),
/// ```
/// {@endtemplate}
class CrdtTextFieldBuilder extends StatefulWidget {
  /// Create a CrdtTextFieldBuilder.
  ///
  /// {@macro crdt_text_field_builder}
  const CrdtTextFieldBuilder({
    required this.id,
    required this.builder,
    this.onSelectionAnchorsChanged,
    this.deletedBuilder,
    super.key,
  });

  /// The id of the text handler to bind (as registered on the document).
  final String id;

  /// Called once with the [TextEditingController] internally handled.
  final Widget Function(
    BuildContext context,
    TextEditingController textEditingController,
  ) builder;

  /// Called whenever the stable anchors of the local selection change
  /// ([CRDTFugueTextHandler.stablePositionAt] of the selection base and
  /// extent) — ready to be published as ephemeral presence (e.g. the
  /// awareness plugin of `crdt_socket_sync`), so that other peers can draw
  /// this user's cursor with `CrdtTextCursorsOverlay`.
  ///
  /// Anchors are only reported **while the field has focus** — a user has
  /// one text cursor, where they are typing. When focus leaves the field
  /// (Flutter keeps the controller's selection on blur) the callback fires
  /// once with `null`s so the published cursor is withdrawn.
  ///
  /// `null` anchors mean "no anchored selection right now": the field is
  /// not focused, has no valid selection, an IME composition is pending, or
  /// the handler is not Fugue-based (only Fugue handlers carry element
  /// identity).
  final void Function(FugueElementID? base, FugueElementID? extent)?
      onSelectionAnchorsChanged;

  /// {@macro crdt_deleted_builder}
  ///
  /// The published anchors are withdrawn with `null`s.
  final WidgetBuilder? deletedBuilder;

  @override
  State<CrdtTextFieldBuilder> createState() => _CrdtTextFieldBuilderState();
}

class _CrdtTextFieldBuilderState extends State<CrdtTextFieldBuilder>
    implements TextFieldContent<String, SequenceDelta<String>> {
  /// Set by the first `build`; everything else runs after one.
  late CRDTDocument _document;

  late final TextFieldEngine<String, SequenceDelta<String>> _engine =
      TextFieldEngine<String, SequenceDelta<String>>(
    this,
    publish: (base, extent) =>
        widget.onSelectionAnchorsChanged?.call(base, extent),
    // Not the generic resolver: this widget accepts two named handlers and
    // says so, which is a better error than "the wrong delta shape".
    resolve: _deltaProviderOf,
  );

  @override
  Widget build(BuildContext context) {
    final document = _document = context.liveDocument('CrdtTextFieldBuilder');
    // Rebuilds only when this flips, so the field still builds once.
    if (context.selectCrdtDocument((doc) => doc.isDeleted(widget.id))) {
      _engine.binding.detach();
      // Not here: the callback is the user's, and this is a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _engine.anchors.clear();
        }
      });
      return buildDeleted(context, widget.deletedBuilder);
    }
    // Covers a new document and a new id alike, which is why there is no
    // `didUpdateWidget`: `build` always runs after one.
    _engine.attach(document, widget.id);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (hasFocus) => _engine.anchors.hasFocus = hasFocus,
      child: widget.builder(context, _engine.controller),
    );
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  DeltaProvider<String, SequenceDelta<String>> _deltaProviderOf(
    BaseCRDTDocument document,
    String id,
  ) {
    // Both text handlers publish this shape; [_handlerOf] refuses anything
    // else.
    return _handlerOf(document, id)
        as DeltaProvider<String, SequenceDelta<String>>;
  }

  Handler<dynamic> _handler() => _handlerOf(_document, widget.id);

  Handler<dynamic> _handlerOf(BaseCRDTDocument document, String id) {
    final handler = document.handlerById(id);
    if (handler is CRDTTextHandler || handler is CRDTFugueTextHandler) {
      return handler!;
    }
    throw FlutterError(
      'CrdtTextFieldBuilder expected a CRDTTextHandler or '
      'CRDTFugueTextHandler registered under id "$id", '
      'but found ${handler ?? 'none'}.',
    );
  }

  @override
  TextEditingController createController(String content) =>
      TextEditingController(text: content);

  @override
  String textOf(String content) => content;

  @override
  int runesOf(String content) => RuneOffsets.length(content);

  @override
  String apply(String base, SequenceDelta<String> delta) =>
      delta.applyToText(base);

  /// A move carries its element along, so it changes nothing here.
  @override
  int netRunes(SequenceDelta<String> delta) {
    var net = 0;
    for (final op in delta.ops) {
      switch (op) {
        case SeqInsert<String>():
          net += op.values.length;
        case SeqDelete<String>():
          net -= op.count;
        case SeqRetain<String>():
        case SeqMove<String>():
          break;
      }
    }
    return net;
  }

  @override
  int Function(int rune) offsetMapper(SequenceDelta<String> delta) =>
      delta.mapOffset;

  @override
  String write(
    String base,
    String baseText,
    TextDelta pushed,
    int index,
    int deleted,
  ) {
    final handler = _handler();
    // One body for both handlers: same `insert` and `delete`, no shared type.
    _document.runInTransaction(() {
      if (deleted > 0) {
        if (handler is CRDTTextHandler) {
          handler.delete(index, deleted);
        } else {
          (handler as CRDTFugueTextHandler).delete(index, deleted);
        }
      }
      if (pushed.inserted.isNotEmpty) {
        if (handler is CRDTTextHandler) {
          handler.insert(index, pushed.inserted);
        } else {
          (handler as CRDTFugueTextHandler).insert(index, pushed.inserted);
        }
      }
    });
    return baseText.replaceRange(
      pushed.index,
      pushed.index + pushed.deleted,
      pushed.inserted,
    );
  }

  @override
  bool echoes(
    List<SequenceDelta<String>> dropped, {
    required int deleted,
    required int inserted,
  }) =>
      echoesSequence(dropped, deleted: deleted, inserted: inserted);

  @override
  String writable(String typed) => typed;

  @override
  void show(TextEditingValue value, String content) {
    _engine.controller.value = value;
  }

  @override
  void showFormats(String content) {}

  /// Whether the field's text still agrees with the handler.
  ///
  /// The text is derived and never read back, so a mistake would leave a
  /// document on screen that does not exist until the next reset. This is the
  /// cheapest question that catches it; see
  /// [debugVerifyCrdtTextFieldProjection] for the strict version and the gap it
  /// closes.
  @override
  bool projectionAgrees() {
    final handler = _handler();
    final text = _engine.committedText;
    final agrees = handler is CRDTFugueTextHandler
        ? handler.length == _engine.committedRunes
        : (handler as CRDTTextHandler).value == text;
    assert(
      !debugVerifyCrdtTextFieldProjection ||
          _engine.binding.provider.value == text,
      'the text derived from the deltas drifted from the handler',
    );
    return agrees;
  }

  @override
  bool get anchored => _document.handlerById(widget.id) is CRDTFugueTextHandler;

  @override
  FugueElementID? anchorAt(int rune) {
    final handler = _document.handlerById(widget.id);
    return handler is CRDTFugueTextHandler
        ? handler.stablePositionAt(rune)
        : null;
  }

  @override
  int? runeOf(FugueElementID anchor) {
    final handler = _document.handlerById(widget.id);
    return handler is CRDTFugueTextHandler
        ? handler.indexOfStablePosition(anchor)
        : null;
  }

  @override
  void selectionSettled() {}

  @override
  void remoteReported(SequenceDelta<String> delta) {}
}
