// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// The document the handler widgets read
extension CrdtViewContext on BuildContext {
  /// The nearest view (one-off read).
  BaseCRDTDocument get crdtView => read<BaseCRDTDocument>();

  /// Rebuilds the caller only when the value derived by [selector] from the
  /// nearest view changes.
  R selectCrdtView<R>(R Function(BaseCRDTDocument view) selector) =>
      select<BaseCRDTDocument, R>(selector);

  /// The live document, for the widgets that cannot draw a frozen view.
  ///
  /// Throws a [FlutterError] under a `CrdtHistoryScope`: they would draw the
  /// live document inside a view that looks frozen.
  CRDTDocument liveDocument(String widget) {
    final live = read<CRDTDocument>();
    if (!identical(crdtView, live)) {
      throw FlutterError(
        '$widget cannot be used inside a CrdtHistoryScope.\n'
        'It reads the live document, not the frozen view. Use '
        'CrdtHandlerBuilder, CrdtHandlerSelector, CrdtHandlerDeltaBuilder or '
        'CrdtHandlerDeltaListener inside the scope.',
      );
    }
    return live;
  }
}
