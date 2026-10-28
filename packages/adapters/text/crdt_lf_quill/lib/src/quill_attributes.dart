// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter_quill/flutter_quill.dart';

bool isQuillBlockKey(String key) => Attribute.blockKeys.contains(key);

MarkExpand quillMarkExpand(String key) {
  if (isQuillBlockKey(key) || key == Attribute.link.key) {
    return MarkExpand.none;
  }
  return MarkExpand.after;
}

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
