// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_quill/src/quill_attributes.dart';

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
        handler.insert(at, op.text);
        _reconcile(handler, at, op.text, op.attributes);
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

// The handler gives new text the marks on its left: set what the editor
// asked for and unset the rest.
void _reconcile(
  CRDTFugueRichTextHandler handler,
  int at,
  String text,
  Map<String, Object?> attributes,
) {
  final newline = [for (final rune in text.runes) rune == 0x0A];
  final count = newline.length;
  final wanted = [
    for (final isNewline in newline)
      quillScopedAttributes(attributes, newline: isNewline),
  ];
  final current = [
    for (var i = 0; i < count; i++) handler.attributesAt(at + i),
  ];
  final keys = <String>{
    for (final map in wanted) ...map.keys,
    for (final map in current) ...map.keys,
  };

  for (final key in keys) {
    var i = 0;
    while (i < count) {
      final value = wanted[i][key];
      if (current[i][key] == value) {
        i++;
        continue;
      }
      if (newline[i]) {
        handler.format(at + i, 1, key, value, expand: MarkExpand.none);
        i++;
        continue;
      }
      var end = i + 1;
      while (end < count &&
          !newline[end] &&
          wanted[end][key] == value &&
          current[end][key] != value) {
        end++;
      }
      handler.format(at + i, end - i, key, value, expand: quillMarkExpand(key));
      i = end;
    }
  }
}
