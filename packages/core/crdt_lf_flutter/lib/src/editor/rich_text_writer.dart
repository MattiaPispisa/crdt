// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/foundation.dart';

/// Writes edits of a rich text editor into a [CRDTFugueRichTextHandler].
///
/// [expandOf] says how the format of a key grows, and [isBlockKey] which keys
/// mark a `'\n'` instead of text. Each method writes many operations: run it
/// inside `runInTransaction` to send them to the other peers together.
class RichTextWriter {
  /// Creates a writer with the key policy of an editor.
  const RichTextWriter({
    required this.expandOf,
    this.isBlockKey = _noBlockKeys,
  });

  /// How a format with a key grows when text is typed at its edge.
  final MarkExpand Function(String key) expandOf;

  /// Whether a key is a block attribute.
  final bool Function(String key) isBlockKey;

  static bool _noBlockKeys(String key) => false;

  /// Whether the writer formats the inline key [key] after an insert instead
  /// of with it.
  bool formatsAfterInsert(String key) =>
      !isBlockKey(key) && expandOf(key) != MarkExpand.after;

  /// Writes [delta] into [handler].
  ///
  /// Inserted text gets exactly the attributes of its insert, not the ones of
  /// the text on its left. A retain or a delete past the end of [handler] is
  /// clamped.
  void write(CRDTFugueRichTextHandler handler, RichTextDelta delta) {
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

  /// Inserts [text] typed at [at], with what the text on its left lends plus
  /// [attributes], and returns it as the handler holds it.
  ///
  /// [attributes] skip each `'\n'`, where an inline key would be a block
  /// attribute. The run before can still expand over the `'\n'`, which shows
  /// nothing: an inline key on a `'\n'` is ignored.
  List<RichTextInsert> insertTyped(
    CRDTFugueRichTextHandler handler,
    int at,
    String text,
    Map<String, Object?> attributes,
  ) {
    if (text.isEmpty) {
      return const [];
    }
    if (attributes.isEmpty) {
      handler.insert(at, text);
    } else {
      var index = at;
      for (final part in _splitNewlines(text)) {
        final newline = part == '\n';
        final length = RuneOffsets.length(part);
        handler.insert(
          index,
          part,
          attributes: newline ? const {} : _withInsert(attributes),
        );
        if (!newline) {
          _formatAfterInsert(handler, index, length, attributes);
        }
        index += length;
      }
    }
    return _read(handler, at, text);
  }

  // `insert` expands its attributes after; another mode needs a format.
  Map<String, Object?> _withInsert(Map<String, Object?> attributes) => {
        for (final entry in attributes.entries)
          if (!formatsAfterInsert(entry.key)) entry.key: entry.value,
      };

  void _formatAfterInsert(
    CRDTFugueRichTextHandler handler,
    int at,
    int count,
    Map<String, Object?> attributes,
  ) {
    for (final entry in attributes.entries) {
      if (formatsAfterInsert(entry.key)) {
        handler.format(
          at,
          count,
          entry.key,
          entry.value,
          expand: expandOf(entry.key),
        );
      }
    }
  }

  void _format(
    CRDTFugueRichTextHandler handler,
    int from,
    int to,
    Map<String, Object?> attributes,
  ) {
    if (attributes.keys.any(isBlockKey)) {
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
        expand: expandOf(entry.key),
      );
    }
  }

  void _insert(
    CRDTFugueRichTextHandler handler,
    int at,
    String text,
    Map<String, Object?> attributes,
  ) {
    handler.insert(
      at,
      text,
      attributes: _withInsert(attributes),
      // The delta holds the exact attributes: drop what the left text would
      // lend.
      inherit: false,
    );
    _formatAfterInsert(handler, at, RuneOffsets.length(text), attributes);
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
      attributes: _withInsert(attributes),
      inherit: false,
    );
    _formatAfterInsert(handler, at, 1, attributes);
  }

  // An editor behind the handler may point at a rune that is not an embed:
  // the new embed then takes its place.
  void _updateEmbed(
    CRDTFugueRichTextHandler handler,
    int index,
    Map<String, Object?> embed,
  ) {
    final text = handler.text;
    if (text.startsWith(
      RichTextSpan.objectReplacement,
      RuneOffsets.utf16Offset(text, index),
    )) {
      handler.updateEmbed(index, embed);
      return;
    }
    _insertEmbed(handler, index, embed, const {});
    handler.delete(index + 1, 1);
  }

  static Iterable<String> _splitNewlines(String text) sync* {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune == 0x0A) {
        if (buffer.isNotEmpty) {
          yield buffer.toString();
          buffer.clear();
        }
        yield '\n';
      } else {
        buffer.writeCharCode(rune);
      }
    }
    if (buffer.isNotEmpty) {
      yield buffer.toString();
    }
  }

  // The inserted runes with the attributes the handler gave them.
  static List<RichTextInsert> _read(
    CRDTFugueRichTextHandler handler,
    int index,
    String text,
  ) {
    final out = <RichTextInsert>[];
    final buffer = StringBuffer();
    Map<String, Object?>? current;
    var rune = index;
    for (final codePoint in text.runes) {
      final attributes = handler.attributesAt(rune++);
      if (current != null && !mapEquals(current, attributes)) {
        out.add(RichTextInsert(buffer.toString(), current));
        buffer.clear();
      }
      current = attributes;
      buffer.writeCharCode(codePoint);
    }
    if (current != null) {
      out.add(RichTextInsert(buffer.toString(), current));
    }
    return out;
  }
}
