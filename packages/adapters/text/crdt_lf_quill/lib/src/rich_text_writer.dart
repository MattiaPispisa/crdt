// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_quill/src/quill_attributes.dart';

/// Writes [delta] into [handler].
///
/// It writes many operations: run it inside `runInTransaction` to send them
/// to the other peers together.
///
/// Inserted text gets exactly the attributes of its insert, not the ones of
/// the text on its left. Formats grow as [quillMarkExpand] says, and block
/// keys mark each newline on its own. A retain or a delete past the end of
/// [handler] is clamped.
void writeRichTextDelta(CRDTFugueRichTextHandler handler, RichTextDelta delta) {
  var index = 0;
  for (final op in delta.ops) {
    switch (op) {
      case RichTextRetain():
        final end = min(index + op.count, handler.length);
        if (op.attributes.isNotEmpty && index < end) {
          _format(handler, index, end, op.attributes);
        }
        index += op.count;
      case RichTextInsert():
        final at = min(index, handler.length);
        _insert(handler, at, op.text, op.attributes);
        index = at + op.length;
      case RichTextDelete():
        final count = min(op.count, handler.length - index);
        if (count > 0) {
          handler.delete(index, count);
        }
    }
  }
}

void _format(
  CRDTFugueRichTextHandler handler,
  int from,
  int to,
  Map<String, Object?> attributes,
) {
  if (attributes.keys.any(isQuillBlockKey)) {
    for (var i = from; i < to; i++) {
      for (final entry in attributes.entries) {
        handler.format(i, 1, entry.key, entry.value, expand: MarkExpand.none);
      }
    }
    return;
  }
  for (final entry in attributes.entries) {
    handler.format(
      from,
      to - from,
      entry.key,
      entry.value,
      expand: quillMarkExpand(entry.key),
    );
  }
}

// Inserted inline text grows after its end, so a key that must not grow is
// formatted on its own.
void _insert(
  CRDTFugueRichTextHandler handler,
  int at,
  String text,
  Map<String, Object?> attributes,
) {
  bool fixed(String key) =>
      !isQuillBlockKey(key) && quillMarkExpand(key) == MarkExpand.none;
  handler.insert(
    at,
    text,
    attributes: {
      for (final entry in attributes.entries)
        if (!fixed(entry.key)) entry.key: entry.value,
    },
    // Quill sends the exact attributes of the insert: drop what the left
    // text would lend.
    inherit: false,
  );
  for (final entry in attributes.entries) {
    if (fixed(entry.key)) {
      handler.format(
        at,
        RuneOffsets.length(text),
        entry.key,
        entry.value,
        expand: MarkExpand.none,
      );
    }
  }
}
