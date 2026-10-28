// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:flutter_quill/flutter_quill.dart';

/// Whether [key] is a Quill block attribute, such as `header` or `list`.
///
/// A block key lives on the `'\n'` that ends a line, an inline key on text.
bool isQuillBlockKey(String key) => Attribute.blockKeys.contains(key);

/// How a format with [key] grows when text is typed at its edge.
///
/// Block keys and `link` never grow ([MarkExpand.none]). Every other key
/// grows after its end ([MarkExpand.after]).
MarkExpand quillMarkExpand(String key) {
  if (isQuillBlockKey(key) || key == Attribute.link.key) {
    return MarkExpand.none;
  }
  return MarkExpand.after;
}

/// The entries of [attributes] that fit a `'\n'` when [newline] is `true`,
/// else the ones that fit text.
///
/// Block keys fit a newline only, inline keys fit text only. A `null` value
/// is kept.
Map<String, Object?> quillScopedAttributes(
  Map<String, Object?> attributes, {
  required bool newline,
}) {
  if (attributes.isEmpty) {
    return const {};
  }
  return {
    for (final entry in attributes.entries)
      if (isQuillBlockKey(entry.key) == newline) entry.key: entry.value,
  };
}
