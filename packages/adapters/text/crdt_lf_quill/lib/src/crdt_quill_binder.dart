// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/src/crdt_quill_binding.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';

class CrdtQuillBinder extends StatefulWidget {
  const CrdtQuillBinder({
    required this.id,
    required this.controller,
    this.child,
    this.builder,
    this.deletedBuilder,
    super.key,
  }) : assert(
         (child == null) != (builder == null),
         'pass either a child or a builder',
       );

  final String id;

  final QuillController controller;

  final Widget? child;

  final WidgetBuilder? builder;

  final WidgetBuilder? deletedBuilder;

  @override
  State<CrdtQuillBinder> createState() => _CrdtQuillBinderState();
}

class _CrdtQuillBinderState extends State<CrdtQuillBinder> {
  late final CrdtQuillBinding _binding = CrdtQuillBinding(widget.controller);

  @override
  void didUpdateWidget(CrdtQuillBinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _binding.controller = widget.controller;
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
