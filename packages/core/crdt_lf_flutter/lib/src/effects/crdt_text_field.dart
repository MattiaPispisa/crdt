import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/effects/_text_sync.dart';
import 'package:flutter/widgets.dart';

export 'package:crdt_lf_flutter/src/effects/_text_sync.dart'
    show debugVerifyCrdtTextFieldProjection;

/// {@template crdt_text_field_builder}
/// Binds a [TextEditingController] to the text handler registered under [id]
/// (`CRDTTextHandler` or `CRDTFugueTextHandler`):
///
/// - **Local edits** are pushed into the handler immediately, as the precise
///   `TextDelta` of each editing gesture (common prefix/suffix trimming — no
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
///   [SequenceDelta] the handler reports, which says exactly what moved even
///   when a change touched several regions. Only a change no delta can
///   describe — a snapshot import, a dropped cache — falls back to a diff of
///   the two texts.
/// - The subtree **never rebuilds**: the widget listens to the document
///   directly and updates the controller, exactly like a headless editor
///   binding. [builder] runs once.
///
/// For text whose formatting lives outside the characters, use
/// `CrdtRichTextFieldBuilder` instead. The two are the same binding underneath.
///
/// ## Example
/// ```dart
/// CrdtTextFieldBuilder(
///   id: 'note',
///   builder: (context, controller) => TextField(controller: controller),
/// ),
/// ```
/// {@endtemplate}
class CrdtTextFieldBuilder extends StatelessWidget {
  /// Create a CrdtTextFieldBuilder.
  ///
  /// {@macro crdt_text_field_builder}
  const CrdtTextFieldBuilder({
    required this.id,
    required this.builder,
    this.onSelectionAnchorsChanged,
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

  @override
  Widget build(BuildContext context) {
    return TextSyncBuilder<String, SequenceDelta<String>>(
      id: id,
      adapterFor: _adapterFor,
      builder: builder,
      onSelectionAnchorsChanged: onSelectionAnchorsChanged,
    );
  }

  static TextHandlerAdapter<String, SequenceDelta<String>> _adapterFor(
    CRDTDocument document,
    String id,
  ) {
    final handler = document.registeredHandlers[id];
    if (handler is CRDTFugueTextHandler) {
      return _FugueTextAdapter(handler);
    }
    if (handler is CRDTTextHandler) {
      return _PlainTextAdapter(handler);
    }
    throw FlutterError(
      'CrdtTextFieldBuilder expected a CRDTTextHandler or '
      'CRDTFugueTextHandler registered under id "$id", '
      'but found ${handler ?? 'none'}.',
    );
  }
}

/// Binds `CRDTTextHandler`, which carries no element identity: the caret rides
/// on the reported delta instead of on an anchor.
class _PlainTextAdapter
    extends TextHandlerAdapter<String, SequenceDelta<String>> {
  _PlainTextAdapter(this._handler);

  final CRDTTextHandler _handler;

  @override
  DeltaProvider<String, SequenceDelta<String>> get provider => _handler;

  @override
  String textOf(String value) => value;

  @override
  SequenceDelta<String>? textDeltaOf(SequenceDelta<String> delta) => delta;

  @override
  void insert(int index, String text) => _handler.insert(index, text);

  @override
  void delete(int index, int count) => _handler.delete(index, count);

  /// There is no cheaper question than the whole string here, so it is the one
  /// asked in release too.
  @override
  bool agreesWith(String text, int runes) => _handler.value == text;
}

/// Binds `CRDTFugueTextHandler`: `length` is an `O(1)` rune count, and every
/// element has an identity the caret can be anchored to.
class _FugueTextAdapter
    extends TextHandlerAdapter<String, SequenceDelta<String>> {
  _FugueTextAdapter(this._handler);

  final CRDTFugueTextHandler _handler;

  @override
  DeltaProvider<String, SequenceDelta<String>> get provider => _handler;

  @override
  String textOf(String value) => value;

  @override
  SequenceDelta<String>? textDeltaOf(SequenceDelta<String> delta) => delta;

  @override
  void insert(int index, String text) => _handler.insert(index, text);

  @override
  void delete(int index, int count) => _handler.delete(index, count);

  @override
  bool agreesWith(String text, int runes) => _handler.length == runes;

  @override
  FugueElementID? stablePositionAt(int runeIndex) =>
      _handler.stablePositionAt(runeIndex);

  @override
  int? indexOfStablePosition(FugueElementID position) =>
      _handler.indexOfStablePosition(position);
}
