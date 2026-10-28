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
/// Put the widgets that listen to [controller] (toolbar, editor) under the
/// binder. A read that arrives during a build runs at the end of the frame.
/// See the README for units, attributes and the last newline.
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

  /// Called with the refused data when [controller] inserts an embed.
  ///
  /// Embeds are not supported: the edit is dropped. The binder wraps the
  /// `onReplaceText` that [controller] had when it was bound; assigning a new
  /// one later removes the refusal.
  final void Function(Object? data)? onUnsupported;

  @override
  State<CrdtQuillBinder> createState() => _CrdtQuillBinderState();
}

class _CrdtQuillBinderState extends State<CrdtQuillBinder> {
  late final CrdtQuillBinding _binding = CrdtQuillBinding(
    widget.controller,
    onUnsupported: widget.onUnsupported,
  );

  @override
  void didUpdateWidget(CrdtQuillBinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _binding
      ..controller = widget.controller
      ..onUnsupported = widget.onUnsupported;
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
      builder: (context, binding) {
        _binding.binding = binding;
        return widget.child ?? widget.builder!(context);
      },
    );
  }
}
