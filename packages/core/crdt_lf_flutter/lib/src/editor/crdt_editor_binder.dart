// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/common/_crdt_guards.dart';
import 'package:crdt_lf_flutter/src/editor/crdt_editor_binding.dart';
import 'package:crdt_lf_flutter/src/provider/_crdt_view.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_helper.dart';
import 'package:crdt_lf_flutter/src/provider/handler_delta_subscription.dart';
import 'package:flutter/widgets.dart';

class CrdtEditorBinder<V, D extends ComposableDelta<D>> extends StatefulWidget {
  const CrdtEditorBinder({
    required this.id,
    required this.onRemoteDelta,
    required this.onReset,
    required this.builder,
    this.verifyProjection,
    this.deletedBuilder,
    super.key,
  });

  final String id;

  final void Function(HandlerDelta<D> delta) onRemoteDelta;

  final void Function(V value, ResetCause cause) onReset;

  final bool Function()? verifyProjection;

  final Widget Function(
    BuildContext context,
    CrdtEditorBinding<V, D> binding,
  ) builder;

  final WidgetBuilder? deletedBuilder;

  @override
  State<CrdtEditorBinder<V, D>> createState() => _CrdtEditorBinderState<V, D>();
}

class _CrdtEditorBinderState<V, D extends ComposableDelta<D>>
    extends State<CrdtEditorBinder<V, D>> {
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
      return buildDeleted(context, widget.deletedBuilder);
    }
    // In build, like the other delta widgets: it covers a new document and a
    // new id, so there is no `didUpdateWidget`.
    _binding.attach(document, widget.id);
    return widget.builder(context, _binding);
  }

  @override
  void dispose() {
    _binding.dispose();
    super.dispose();
  }
}
