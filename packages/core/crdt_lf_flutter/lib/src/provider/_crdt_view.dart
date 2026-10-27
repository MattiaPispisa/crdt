// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// The document the handler widgets read: the frozen one under a
/// `CrdtHistoryScope`, the live one otherwise.
extension CrdtViewContext on BuildContext {
  bool get _inHistoryScope => read<BaseCRDTDocument?>() != null;

  /// The nearest view (one-off read).
  BaseCRDTDocument get crdtView =>
      read<BaseCRDTDocument?>() ?? read<CRDTDocument>();

  /// Rebuilds the caller only when the value derived by [selector] from the
  /// nearest view changes.
  R selectCrdtView<R>(R Function(BaseCRDTDocument view) selector) =>
      _inHistoryScope
          ? select<BaseCRDTDocument, R>(selector)
          : select<CRDTDocument, R>(selector);

  /// The live document, for the widgets that cannot draw a frozen view.
  ///
  /// Throws a [FlutterError] under a `CrdtHistoryScope`: they would draw the
  /// live document inside a view that looks frozen.
  CRDTDocument liveDocument(String widget) {
    if (_inHistoryScope) {
      throw FlutterError(
        '$widget cannot be used inside a CrdtHistoryScope.\n'
        'It reads the live document, not the frozen view. Use '
        'CrdtHandlerBuilder, CrdtHandlerSelector, CrdtHandlerDeltaBuilder or '
        'CrdtHandlerDeltaListener inside the scope.',
      );
    }
    return read<CRDTDocument>();
  }
}
