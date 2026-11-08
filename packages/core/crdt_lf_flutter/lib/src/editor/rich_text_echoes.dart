// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/editor/rich_text_writer.dart';

/// Whether a format of [attributes] on the runes `[from, to)` is part of a
/// write.
typedef OwnsFormat = bool Function(
  int from,
  int to,
  Map<String, Object?> attributes,
);

/// An [OwnsFormat] for the formats a write puts on `[from, to)`: each key
/// set to its value in [attributes].
OwnsFormat formatsWithin(int from, int to, Map<String, Object?> attributes) =>
    (start, end, written) =>
        start >= from &&
        end <= to &&
        written.entries.every(
          (entry) =>
              attributes.containsKey(entry.key) &&
              attributes[entry.key] == entry.value,
        );

/// Whether [dropped] holds nothing but a rich text write of [deleted] and
/// [inserted] runes.
///
/// Made for the `isEcho` of `CrdtEditorBinding.push`. A write of another
/// writer during the push, even one that keeps the length of the text (a
/// format, an embed update), gives `false`, so the editor reads the handler
/// again.
///
/// [embedsInserted] and [embedsUpdated] count the embeds the write puts in
/// and updates. A format is the write's own when [ownsFormat] says so, in the
/// coordinates of the delta that holds it; `null` owns no format.
bool echoesRichText(
  List<RichTextDelta> dropped, {
  required int deleted,
  required int inserted,
  int embedsInserted = 0,
  int embedsUpdated = 0,
  OwnsFormat? ownsFormat,
}) {
  bool owns(int from, int to, Map<String, Object?> attributes) =>
      attributes.isEmpty || (ownsFormat?.call(from, to, attributes) ?? false);

  var totalIn = 0;
  var totalOut = 0;
  var embedsIn = 0;
  var embedsUp = 0;
  for (final delta in dropped) {
    var at = 0;
    for (final op in delta.ops) {
      switch (op) {
        case RichTextInsert():
          totalIn += op.length;
          at += op.length;
        case RichTextInsertEmbed():
          embedsIn++;
          at++;
        case RichTextUpdateEmbed():
          embedsUp++;
          if (!owns(at, at + 1, op.attributes)) {
            return false;
          }
          at++;
        case RichTextDelete():
          totalOut += op.count;
        case RichTextRetain():
          if (!owns(at, at + op.count, op.attributes)) {
            return false;
          }
          at += op.count;
      }
    }
  }
  return totalIn == inserted &&
      totalOut == deleted &&
      embedsIn == embedsInserted &&
      embedsUp == embedsUpdated;
}

/// What one write of a [RichTextWriter] puts in the handler, to tell its echo
/// from a foreign change.
class RichTextEcho {
  /// Creates an empty record.
  RichTextEcho(this._writer);

  final RichTextWriter _writer;

  int _inserted = 0;
  int _deleted = 0;
  int _embedsInserted = 0;
  int _embedsUpdated = 0;
  final List<OwnsFormat> _formats = [];

  /// Records [delta], a write in the coordinates of the handler it met.
  void add(RichTextDelta delta) {
    var index = 0;
    void own(int count, Map<String, Object?> attributes) {
      if (attributes.isNotEmpty) {
        _formats.add(formatsWithin(index, index + count, attributes));
      }
      index += count;
    }

    // The write clears what the insert takes from its left. A key formatted
    // after the insert goes `null` first; once set, a `null` is foreign.
    void put(int count, Map<String, Object?> attributes) {
      final from = index;
      final to = index += count;
      final unset = attributes.keys.where(_writer.formatsAfterInsert).toSet();
      _formats.add((start, end, written) {
        if (start < from || end > to) {
          return false;
        }
        return written.entries.every((entry) {
          final key = entry.key;
          final clear = entry.value == null;
          final own =
              attributes[key] == entry.value || clear && unset.contains(key);
          if (!clear) {
            unset.remove(key);
          }
          return own;
        });
      });
    }

    for (final op in delta.ops) {
      switch (op) {
        case RichTextRetain():
          own(op.count, op.attributes);
        case RichTextInsert():
          _inserted += op.length;
          put(op.length, op.attributes);
        case RichTextInsertEmbed():
          _embedsInserted++;
          put(1, op.attributes);
        case RichTextUpdateEmbed():
          _embedsUpdated++;
          own(1, op.attributes);
        case RichTextDelete():
          _deleted += op.count;
      }
    }
  }

  /// Whether a format belongs to the recorded writes.
  bool ownsFormat(int from, int to, Map<String, Object?> attributes) =>
      _formats.any((owns) => owns(from, to, attributes));

  /// Whether [dropped] holds nothing but the recorded writes.
  ///
  /// Made for the `isEcho` of `CrdtEditorBinding.push`.
  bool echoes(List<RichTextDelta> dropped) => echoesRichText(
        dropped,
        deleted: _deleted,
        inserted: _inserted,
        embedsInserted: _embedsInserted,
        embedsUpdated: _embedsUpdated,
        ownsFormat: ownsFormat,
      );
}
