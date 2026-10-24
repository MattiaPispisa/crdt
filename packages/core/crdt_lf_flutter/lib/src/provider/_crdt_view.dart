// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// The document the handler widgets read: the live one, or the frozen view
/// of the nearest `CrdtHistoryScope`.
extension CrdtViewContext on BuildContext {
  /// The nearest view (one-off read).
  BaseCRDTDocument get crdtView => read<BaseCRDTDocument>();

  /// Rebuilds the caller only when the value derived by [selector] from the
  /// nearest view changes.
  R selectCrdtView<R>(R Function(BaseCRDTDocument view) selector) =>
      select<BaseCRDTDocument, R>(selector);
}
