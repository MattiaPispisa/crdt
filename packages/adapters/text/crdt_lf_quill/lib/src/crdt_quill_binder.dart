// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/src/crdt_quill_binding.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Keeps a `QuillController` in step with the [CRDTFugueRichTextHandler]
/// [id] of the document from `CrdtProvider`.
///
/// It renders [child], or [builder], and [deletedBuilder] once the handler
/// is deleted. It rebuilds only when the document or the deleted state
/// changes: the editor follows the handler through the controller.
///
/// After it attaches, [controller] holds a `Document` owned by the binder.
/// Assigning `controller.document` yourself unbinds that document: its edits
/// stay out of the handler, and the next read of the handler replaces it.
/// Peer changes stay out of the undo stack, like `History(userOnly: true)`.
///
/// A change that arrives during a build reaches [controller] at the end of
/// the frame. The [guide](https://mattiapispisa.it/crdt/docs/connectors/flutter/editors/quill)
/// covers units, attributes, embeds and the last newline.
///
/// Throws a `FlutterError` when [id] is not a rich text handler.
class CrdtQuillBinder extends StatefulWidget {
  /// Creates a binder; pass either [child] or [builder].
  const CrdtQuillBinder({
    required this.id,
    required this.controller,
    this.child,
    this.builder,
    this.deletedBuilder,
    this.onUnsupported,
    this.embedTypes,
    this.undoManager,
    this.onSelectionAnchorsChanged,
    super.key,
  }) : assert(
         (child == null) != (builder == null),
         'pass either a child or a builder',
       );

  /// The id of the [CRDTFugueRichTextHandler] to bind.
  ///
  /// A new id reads that handler into [controller].
  final String id;

  /// The controller to bind; a new one gets the handler content.
  final QuillController controller;

  /// The subtree to show; `null` when [builder] is set.
  final Widget? child;

  /// Builds the subtree to show; `null` when [child] is set.
  final WidgetBuilder? builder;

  /// Builds what shows once the handler is deleted; an empty box when `null`.
  final WidgetBuilder? deletedBuilder;

  /// Called with each embed [controller] inserts that [embedTypes] or the
  /// handler refuses (see [CRDTFugueRichTextHandler.checkEmbed]), and with
  /// `{key: value}` for each attribute value the handler refuses (see
  /// [CRDTFugueRichTextHandler.checkAttribute]).
  ///
  /// The rest of the edit is written, and a refused embed never deletes an
  /// embed (see "Embeds" in the guide). The binder wraps the `onReplaceText`
  /// that [controller] had when it was bound; assigning a new one later
  /// removes the refusal.
  final void Function(Object? data)? onUnsupported;

  /// The types of the Quill embeds the editor writes to the handler; `null`
  /// takes all.
  ///
  /// A peer can still write any type: use `crdtQuillUnknownEmbedBuilder` so
  /// the editor can show it.
  final Set<String>? embedTypes;

  /// The manager that undoes and redoes; `null` keeps Quill's own history.
  /// A new manager drops the steps of that history.
  ///
  /// Track the handler with it and pass [crdtQuillOrigin] in its
  /// `trackedOrigins`. Undo then takes back your own edits only, formats
  /// included, and a peer's concurrent edit survives it.
  final CRDTUndoManager? undoManager;

  /// Called when the stable anchors of the selection change, while focus is
  /// inside the subtree.
  ///
  /// It fires once with `null`s when the focus leaves or the handler is
  /// deleted. Publish the anchors to the other peers and draw them with
  /// `CrdtQuillCursorsOverlay`.
  final void Function(FugueElementID? base, FugueElementID? extent)?
  onSelectionAnchorsChanged;

  @override
  State<CrdtQuillBinder> createState() => _CrdtQuillBinderState();
}

class _CrdtQuillBinderState extends State<CrdtQuillBinder> {
  late final CrdtQuillBinding _binding;

  @override
  void initState() {
    super.initState();
    _binding = CrdtQuillBinding(
      widget.controller,
      onUnsupported: widget.onUnsupported,
      embedTypes: widget.embedTypes,
      undoManager: widget.undoManager,
      onSelectionAnchorsChanged: widget.onSelectionAnchorsChanged,
    )..bind();
  }

  @override
  void didUpdateWidget(CrdtQuillBinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _binding
      ..controller = widget.controller
      ..onUnsupported = widget.onUnsupported
      ..embedTypes = widget.embedTypes
      ..undoManager = widget.undoManager
      ..onSelectionAnchorsChanged = widget.onSelectionAnchorsChanged;
  }

  @override
  void dispose() {
    _binding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CrdtEditorBinder<List<RichTextSpan>, RichTextDelta>(
      id: widget.id,
      onRemoteDelta: _binding.onRemoteDelta,
      onReset: _binding.onReset,
      verifyProjection: _binding.verifyProjection,
      deletedBuilder: widget.deletedBuilder,
      anchors: _binding.anchors,
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          _binding.captureAnchors();
        }
      },
      builder: (context, binding) {
        _binding.binding = binding;
        return widget.child ?? widget.builder!(context);
      },
    );
  }
}
