// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:flutter/services.dart';

/// Copies a text for the user.
///
/// In DevTools it must go through `extensionManager.copyToClipboard`,
/// which also works when DevTools is embedded in an IDE.
class TextCopier {
  const TextCopier(this._copy);

  /// Copies to the system clipboard.
  static const TextCopier clipboard = TextCopier(_toClipboard);

  final void Function(String text) _copy;

  /// Copies [text].
  void call(String text) => _copy(text);

  static void _toClipboard(String text) =>
      unawaited(Clipboard.setData(ClipboardData(text: text)));
}
