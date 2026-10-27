// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_helper.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Builder invoked by [CrdtHistoryScope] on every cursor move.
typedef CrdtHistoryWidgetBuilder = Widget Function(
  BuildContext context,
  HistorySession session,
  Widget? child,
);

/// Shows the ambient document frozen at a point of its history.
///
/// The handler widgets below (`CrdtHandlerBuilder`, `CrdtHandlerSelector`,
/// `CrdtHandlerListener`) read the frozen view instead of the live document,
/// so the same widgets draw both.
class CrdtHistoryScope extends StatefulWidget {
  /// Creates a scope over a snapshot of the ambient document.
  const CrdtHistoryScope({required this.builder, this.child, super.key});

  /// Called on every cursor move with the session that drives the view.
  final CrdtHistoryWidgetBuilder builder;

  /// The subtree that does not depend on the cursor, passed to [builder]
  /// as is so it is not rebuilt on every move.
  final Widget? child;

  @override
  State<CrdtHistoryScope> createState() => _CrdtHistoryScopeState();
}

class _CrdtHistoryScopeState extends State<CrdtHistoryScope> {
  HistorySession? _session;
  CRDTDocument? _source;

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds only when the provided document is replaced.
    final document = context.selectCrdtDocument((document) => document);
    if (!identical(document, _source)) {
      // The snapshot is taken once per document: the cursor is an index.
      _session?.dispose();
      _source = document;
      _session = document.toTimeTravel();
    }
    final session = _session!;
    return InheritedProvider<BaseCRDTDocument>.value(
      value: session.document,
      startListening: (element, _) => session.cursorStream
          .listen((_) => element.markNeedsNotifyDependents())
          .cancel,
      child: Builder(
        builder: (context) {
          context.watch<BaseCRDTDocument>();
          return widget.builder(context, session, widget.child);
        },
      ),
    );
  }
}
