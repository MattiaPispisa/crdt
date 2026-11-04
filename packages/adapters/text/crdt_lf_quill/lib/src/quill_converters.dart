// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_quill/src/quill_attributes.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter_quill/flutter_quill.dart' show Embeddable;

/// The Quill change for [delta], a change of a [CRDTFugueRichTextHandler].
///
/// {@template crdt_lf_quill.units}
/// The handler counts runes and Quill counts UTF-16 code units. [before] is
/// the Quill plain text the change applies to: the offsets are translated
/// against it.
/// {@endtemplate}
///
/// Attributes are split by scope (see [quillScopedAttributes]). A `null`
/// value removes the attribute on a retain and is dropped on an insert.
///
/// An embed is a Quill embed insert of the same map. An updated embed is an
/// insert and a delete; [document], the Quill document [before] comes from,
/// gives the attributes it keeps.
Delta quillDeltaFromRichText(
  RichTextDelta delta,
  String before, {
  Delta? document,
}) {
  final result = Delta();
  var unit = 0;
  for (final op in delta.ops) {
    switch (op) {
      case RichTextRetain():
        final end = RuneOffsets.skip(before, unit, op.count);
        if (op.attributes.isEmpty) {
          result.retain(end - unit);
        } else {
          _forEachLine(before.substring(unit, end), (
            piece, {
            required newline,
          }) {
            final attributes = quillScopedAttributes(
              op.attributes,
              newline: newline,
            );
            result.retain(piece.length, attributes.isEmpty ? null : attributes);
          });
        }
        unit = end;
      case RichTextInsert():
        _forEachLine(op.text, (piece, {required newline}) {
          final attributes = _withoutNull(
            quillScopedAttributes(op.attributes, newline: newline),
          );
          result.insert(piece, attributes.isEmpty ? null : attributes);
        });
      case RichTextDelete():
        final end = RuneOffsets.skip(before, unit, op.count);
        result.delete(end - unit);
        unit = end;
      case RichTextInsertEmbed():
        final attributes = _withoutNull(
          quillScopedAttributes(op.attributes, newline: false),
        );
        result.insert(
          quillEmbed(op.embed),
          attributes.isEmpty ? null : attributes,
        );
      case RichTextUpdateEmbed():
        final attributes = <String, Object?>{
          if (document != null) ..._attributesAt(document, unit),
          ...quillScopedAttributes(op.attributes, newline: false),
        }..removeWhere((_, value) => value == null);
        result
          ..insert(quillEmbed(op.embed), attributes.isEmpty ? null : attributes)
          ..delete(1);
        unit = RuneOffsets.skip(before, unit, 1);
    }
  }
  return result..trim();
}

/// The [RichTextDelta] for [change], a Quill change.
///
/// {@macro crdt_lf_quill.units}
///
/// Attributes are split by scope, as in [quillDeltaFromRichText]. A Quill
/// embed is a [RichTextInsertEmbed] of the same map. With [document], the
/// Quill document [before] comes from, an embed that replaces an embed in
/// the same change is a [RichTextUpdateEmbed].
RichTextDelta richTextDeltaFromQuill(
  Delta change,
  String before, {
  Delta? document,
}) {
  final ops = <RichTextOp>[];
  final quill = change.toList();
  var unit = 0;
  // Code units of the next delete already taken by an update.
  var updated = 0;
  for (var o = 0; o < quill.length; o++) {
    final op = quill[o];
    final length = (op.length ?? 0) - updated;
    updated = 0;
    if (op.isInsert) {
      final data = op.data;
      if (data is! String) {
        final embed = richTextEmbed(data);
        final attributes = _withoutNull(
          quillScopedAttributes(op.attributes ?? const {}, newline: false),
        );
        final next = o + 1 < quill.length ? quill[o + 1] : null;
        if (document != null &&
            next != null &&
            next.isDelete &&
            unit < before.length &&
            before.codeUnitAt(unit) == _objectReplacement) {
          ops.add(
            RichTextUpdateEmbed(
              embed,
              _changedAttributes(_attributesAt(document, unit), attributes),
            ),
          );
          unit++;
          updated = 1;
          continue;
        }
        ops.add(RichTextInsertEmbed(embed, attributes));
        continue;
      }
      final attributes = op.attributes ?? const {};
      _forEachLine(data, (piece, {required newline}) {
        ops.add(
          RichTextInsert(
            piece,
            _withoutNull(quillScopedAttributes(attributes, newline: newline)),
          ),
        );
      });
      continue;
    }
    final end = unit + length > before.length ? before.length : unit + length;
    final covered = before.substring(unit, end);
    unit = end;
    if (op.isDelete) {
      if (covered.isNotEmpty) {
        ops.add(RichTextDelete(RuneOffsets.length(covered)));
      }
      continue;
    }
    final attributes = op.attributes;
    if (attributes == null || attributes.isEmpty) {
      ops.add(RichTextRetain(RuneOffsets.length(covered)));
      continue;
    }
    _forEachLine(covered, (piece, {required newline}) {
      ops.add(
        RichTextRetain(
          RuneOffsets.length(piece),
          quillScopedAttributes(attributes, newline: newline),
        ),
      );
    });
  }
  return RichTextDelta(ops);
}

/// The Quill document for [spans], the value of a
/// [CRDTFugueRichTextHandler].
///
/// It ends with Quill's last `'\n'`: added when the handler does not store
/// it (see the README, "The last newline").
Delta quillDocumentFromSpans(List<RichTextSpan> spans) {
  final result = Delta();
  for (final span in spans) {
    final embed = span.embed;
    if (embed != null) {
      final attributes = quillScopedAttributes(span.attributes, newline: false);
      result.insert(quillEmbed(embed), attributes.isEmpty ? null : attributes);
      continue;
    }
    _forEachLine(span.text, (piece, {required newline}) {
      final attributes = quillScopedAttributes(
        span.attributes,
        newline: newline,
      );
      result.insert(piece, attributes.isEmpty ? null : attributes);
    });
  }
  // A plain last line keeps Quill's last newline out of the handler.
  if (!trailingNewline(result).stored) {
    result.insert('\n');
  }
  return result;
}

/// Whether the handler stores the last newline of [document], a Quill
/// document, once [skip] code units are dropped from its end.
///
/// It is stored when one of the newlines that end the text has a block
/// attribute. `fromEnd` is the offset of the last such newline, in code
/// units from the end, after [skip].
({bool stored, int fromEnd}) trailingNewline(Delta document, {int skip = 0}) {
  const none = (stored: false, fromEnd: 0);
  final ops = document.toList();
  var index = 0;
  for (var o = ops.length - 1; o >= 0; o--) {
    final op = ops[o];
    final data = op.data;
    if (!op.isInsert || data is! String) {
      return none;
    }
    for (var u = data.length - 1; u >= 0; u--, index++) {
      if (index < skip) {
        continue;
      }
      if (data.codeUnitAt(u) != _newline) {
        return none;
      }
      if (_hasBlock(op.attributes)) {
        return (stored: true, fromEnd: index - skip);
      }
    }
  }
  return none;
}

/// The Quill embed type that holds a handler embed whole.
///
/// A handler embed that is not one key, or whose key is this one, goes to
/// Quill as `{crdtQuillEmbedType: embed}`.
const String crdtQuillEmbedType = 'crdt_lf';

/// The Quill embed for [embed], the data of a handler embed.
///
/// A map of one key is the same map: Quill reads the key as the embed type.
/// Any other map is wrapped in [crdtQuillEmbedType].
Map<String, dynamic> quillEmbed(Map<String, Object?> embed) =>
    embed.length == 1 && embed.keys.single != crdtQuillEmbedType
    ? Map<String, dynamic>.of(embed)
    : {crdtQuillEmbedType: embed};

/// The handler embed for [data], the insert of a Quill embed: an
/// [Embeddable] or its map.
///
/// A [crdtQuillEmbedType] embed gives back the map it wraps.
Map<String, Object?> richTextEmbed(Object? data) {
  final map = switch (data) {
    Embeddable() => {data.type: data.data},
    Map<dynamic, dynamic>() => data.cast<String, Object?>(),
    _ => throw ArgumentError.value(data, 'data', 'is not a Quill embed'),
  };
  final wrapped = map.length == 1 ? map[crdtQuillEmbedType] : null;
  if (wrapped is Map<dynamic, dynamic>) {
    return Map<String, Object?>.of(wrapped.cast<String, Object?>());
  }
  return Map<String, Object?>.of(map);
}

const int _newline = 0x0A;
const int _objectReplacement = 0xFFFC;

// The inline attributes of the Quill op that holds the code unit [unit].
Map<String, Object?> _attributesAt(Delta document, int unit) {
  var index = 0;
  for (final op in document.toList()) {
    final length = op.length ?? 0;
    if (unit < index + length) {
      return quillScopedAttributes(op.attributes ?? const {}, newline: false);
    }
    index += length;
  }
  return const {};
}

// What turns [old] into [now]: changed keys, and removed ones set to `null`.
Map<String, Object?> _changedAttributes(
  Map<String, Object?> old,
  Map<String, Object?> now,
) => {
  for (final entry in now.entries)
    if (old[entry.key] != entry.value) entry.key: entry.value,
  for (final key in old.keys)
    if (!now.containsKey(key)) key: null,
};

bool _hasBlock(Map<String, dynamic>? attributes) =>
    attributes != null &&
    attributes.entries.any(
      (entry) => entry.value != null && isQuillBlockKey(entry.key),
    );

void _forEachLine(
  String text,
  void Function(String piece, {required bool newline}) visit,
) {
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) != _newline) {
      continue;
    }
    if (start < i) {
      visit(text.substring(start, i), newline: false);
    }
    visit('\n', newline: true);
    start = i + 1;
  }
  if (start < text.length) {
    visit(text.substring(start), newline: false);
  }
}

Map<String, Object?> _withoutNull(Map<String, Object?> attributes) {
  if (!attributes.containsValue(null)) {
    return attributes;
  }
  return {
    for (final entry in attributes.entries)
      if (entry.value != null) entry.key: entry.value,
  };
}
