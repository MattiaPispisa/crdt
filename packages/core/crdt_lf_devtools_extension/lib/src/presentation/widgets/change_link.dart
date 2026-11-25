// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/foundation.dart';

/// A request to show a change in the Changes tab.
///
/// The request waits until a listener, or a new tab, [take]s it.
class ChangeLink extends ChangeNotifier {
  OperationId? _pending;

  /// Asks to show the change [id].
  void open(OperationId id) {
    _pending = id;
    notifyListeners();
  }

  /// The waiting request, which it clears; `null` when there is none.
  OperationId? take() {
    final id = _pending;
    _pending = null;
    return id;
  }
}
