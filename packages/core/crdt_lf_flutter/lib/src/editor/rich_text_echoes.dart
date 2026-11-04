// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';

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
