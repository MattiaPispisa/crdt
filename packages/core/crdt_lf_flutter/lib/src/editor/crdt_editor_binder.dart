// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/common/_crdt_guards.dart';
import 'package:crdt_lf_flutter/src/editor/crdt_editor_binding.dart';
import 'package:crdt_lf_flutter/src/editor/selection_anchors.dart';
import 'package:crdt_lf_flutter/src/provider/_crdt_view.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_helper.dart';
import 'package:crdt_lf_flutter/src/provider/handler_delta_subscription.dart';
import 'package:flutter/widgets.dart';

/// Binds an editor to the handler registered under [id], through a
/// [CrdtEditorBinding] it owns.
///
/// It attaches the binding to the ambient document and renders [builder]
/// with it. A change of the handler never rebuilds it: the binding moves the
/// editor instead. It rebuilds only when its parent does or when the handler
/// is deleted.
///
/// Throws a [FlutterError] when [id] holds no handler of the `<V, D>` shape,
/// or inside a `CrdtHistoryScope`.
///
/// ```dart
/// CrdtEditorBinder<List<RichTextSpan>, RichTextDelta>(
///   id: 'page',
///   onReset: (spans, cause) => editor.load(spans),
///   onRemoteDelta: (event) => editor.applyRemote(event.delta),
///   builder: (context, binding) => MyEditor(
///     onLocalEdit: (index, text) => binding.push(
///       () => page.insert(index, text),
///     ),
///   ),
/// );
/// ```
class CrdtEditorBinder<V, D extends ComposableDelta<D>> extends StatefulWidget {
  /// Creates a binder for the handler registered under [id].
  const CrdtEditorBinder({
    required this.id,
    required this.onRemoteDelta,
    required this.onReset,
    required this.builder,
    this.verifyProjection,
    this.deletedBuilder,
    this.onBeforeAttach,
    this.anchors,
    this.onFocusChange,
    super.key,
  });

  /// The id of the handler to bind, as registered on the document.
  final String id;

  /// See [CrdtEditorBinding.onRemoteDelta].
  final void Function(HandlerDelta<D> delta) onRemoteDelta;

  /// See [CrdtEditorBinding.onReset].
  ///
  /// The call made on attach runs inside `build`: it must not call
  /// `setState`.
  final void Function(V value, ResetCause cause) onReset;

  /// See [CrdtEditorBinding.verifyProjection]; `null` to skip the check.
  final bool Function()? verifyProjection;

  /// Builds the editor; write its local edits through
  /// [CrdtEditorBinding.push].
  final Widget Function(
    BuildContext context,
    CrdtEditorBinding<V, D> binding,
  ) builder;

  /// {@macro crdt_deleted_builder}
  ///
  /// The binding stops following the handler.
  final WidgetBuilder? deletedBuilder;

  /// See `onBeforeAttach` of [CrdtEditorBinding.attach].
  final VoidCallback? onBeforeAttach;

  /// The anchors of the selection of the editor, if it has any.
  ///
  /// They hear of the focus inside the subtree, and are cleared when the
  /// binder follows another handler or the handler is deleted.
  final SelectionAnchors? anchors;

  /// See [SelectionAnchorsFocus.onFocusChange]; needs [anchors].
  final ValueChanged<bool>? onFocusChange;

  @override
  State<CrdtEditorBinder<V, D>> createState() => _CrdtEditorBinderState<V, D>();
}

class _CrdtEditorBinderState<V, D extends ComposableDelta<D>>
    extends State<CrdtEditorBinder<V, D>> {
  // Through `widget`, so the callbacks of the latest build are the ones called.
  late final CrdtEditorBinding<V, D> _binding = CrdtEditorBinding<V, D>(
    onRemoteDelta: (delta) => widget.onRemoteDelta(delta),
    onReset: (value, cause) => widget.onReset(value, cause),
    verifyProjection: () => widget.verifyProjection?.call() ?? true,
    resolve: (document, id) =>
        resolveDeltaProvider<V, D>(document, id, 'CrdtEditorBinder'),
  );

  @override
  Widget build(BuildContext context) {
    final document = context.liveDocument('CrdtEditorBinder');
    if (context.selectCrdtDocument((doc) => doc.isDeleted(widget.id))) {
      _binding.detach();
      widget.anchors?.clearAfterFrame(mounted: () => mounted);
      return buildDeleted(context, widget.deletedBuilder);
    }
    // In build, like the other delta widgets: it covers a new document and a
    // new id, so there is no `didUpdateWidget`.
    _binding.attach(
      document,
      widget.id,
      onBeforeAttach: () {
        widget.anchors?.clear();
        widget.onBeforeAttach?.call();
      },
    );
    final child = widget.builder(context, _binding);
    final anchors = widget.anchors;
    return anchors == null
        ? child
        : SelectionAnchorsFocus(
            anchors: anchors,
            onFocusChange: widget.onFocusChange,
            child: child,
          );
  }

  @override
  void dispose() {
    _binding.dispose();
    super.dispose();
  }
}
