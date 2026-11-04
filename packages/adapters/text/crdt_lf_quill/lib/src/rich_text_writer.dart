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
      case RichTextInsertEmbed():
        final at = min(index, handler.length);
        _insertEmbed(handler, at, op.embed, op.attributes);
        index = at + 1;
      case RichTextUpdateEmbed():
        if (index < handler.length) {
          _updateEmbed(handler, index, op.embed);
          if (op.attributes.isNotEmpty) {
            _format(handler, index, index + 1, op.attributes);
          }
        }
        index++;
    }
  }
}

// An editor behind the handler may point at a rune that is not an embed:
// the new embed then takes its place.
void _updateEmbed(
  CRDTFugueRichTextHandler handler,
  int index,
  Map<String, Object?> embed,
) {
  final text = handler.text;
  if (text.codeUnitAt(RuneOffsets.utf16Offset(text, index)) ==
      RichTextSpan.objectReplacement.codeUnitAt(0)) {
    handler.updateEmbed(index, embed);
    return;
  }
  _insertEmbed(handler, index, embed, const {});
  handler.delete(index + 1, 1);
}

void _insertEmbed(
  CRDTFugueRichTextHandler handler,
  int at,
  Map<String, Object?> embed,
  Map<String, Object?> attributes,
) {
  handler.insertEmbed(
    at,
    embed,
    attributes: {
      for (final entry in attributes.entries)
        if (!_fixed(entry.key)) entry.key: entry.value,
    },
    inherit: false,
  );
  _formatFixed(handler, at, 1, attributes);
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
  handler.insert(
    at,
    text,
    attributes: {
      for (final entry in attributes.entries)
        if (!_fixed(entry.key)) entry.key: entry.value,
    },
    // Quill sends the exact attributes of the insert: drop what the left
    // text would lend.
    inherit: false,
  );
  _formatFixed(handler, at, RuneOffsets.length(text), attributes);
}

bool _fixed(String key) =>
    !isQuillBlockKey(key) && quillMarkExpand(key) == MarkExpand.none;

void _formatFixed(
  CRDTFugueRichTextHandler handler,
  int at,
  int count,
  Map<String, Object?> attributes,
) {
  for (final entry in attributes.entries) {
    if (_fixed(entry.key)) {
      handler.format(
        at,
        count,
        entry.key,
        entry.value,
        expand: MarkExpand.none,
      );
    }
  }
}
