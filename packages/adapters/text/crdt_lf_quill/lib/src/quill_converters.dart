// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_quill/src/quill_attributes.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter_quill/flutter_quill.dart' show Attribute, Embeddable;

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
/// An embed is a Quill embed insert (see [crdtQuillEmbedType] for the
/// shapes), and the `displayWidth` mark is the `width` of the Quill `style`.
/// An updated embed is an insert and a delete;
/// [document], the Quill document [before] comes from, gives the attributes
/// it keeps.
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
          var at = unit;
          _forEachLine(before.substring(unit, end), (
            piece, {
            required newline,
          }) {
            final attributes = quillScopedAttributes(
              op.attributes,
              newline: newline,
            );
            if (document == null || !_touchesSize(attributes)) {
              final quill = quillAttributes(attributes);
              result.retain(piece.length, quill.isEmpty ? null : quill);
            } else {
              _forEachRun(document, at, piece.length, (length, current) {
                final quill = quillAttributes(
                  attributes,
                  current: richTextAttributes(current),
                );
                result.retain(length, quill.isEmpty ? null : quill);
              });
            }
            at += piece.length;
          });
        }
        unit = end;
      case RichTextInsert():
        _forEachLine(op.text, (piece, {required newline}) {
          final attributes = _withoutNull(
            quillAttributes(
              quillScopedAttributes(op.attributes, newline: newline),
            ),
          );
          result.insert(piece, attributes.isEmpty ? null : attributes);
        });
      case RichTextDelete():
        final end = RuneOffsets.skip(before, unit, op.count);
        result.delete(end - unit);
        unit = end;
      case RichTextInsertEmbed():
        final attributes = _withoutNull(
          quillAttributes(quillScopedAttributes(op.attributes, newline: false)),
        );
        result.insert(
          quillEmbed(op.embed),
          attributes.isEmpty ? null : attributes,
        );
      case RichTextUpdateEmbed():
        final attributes = _withoutNull(
          quillAttributes({
            if (document != null)
              ...richTextAttributes(_attributesAt(document, unit)),
            ...quillScopedAttributes(op.attributes, newline: false),
          }),
        );
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
/// An offset inside a surrogate pair moves to a rune boundary: a plain retain
/// stops before the pair, and a delete or a format takes the whole rune.
///
/// Attributes are split by scope, as in [quillDeltaFromRichText]. A Quill
/// embed is a [RichTextInsertEmbed] (see [crdtQuillEmbedType] for the
/// shapes), and a px width of the Quill `style` is the `displayWidth` mark.
/// With [document], the
/// Quill document [before] comes from, an embed that replaces an embed in
/// the same change is a [RichTextUpdateEmbed].
RichTextDelta richTextDeltaFromQuill(
  Delta change,
  String before, {
  Delta? document,
}) {
  final ops = <RichTextOp>[];
  final quill = change.toList();
  // [at] is the offset in Quill, [unit] the rune boundary reached in [before].
  var at = 0;
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
          richTextAttributes(
            quillScopedAttributes(op.attributes ?? const {}, newline: false),
          ),
        );
        final next = o + 1 < quill.length ? quill[o + 1] : null;
        if (document != null &&
            next != null &&
            next.isDelete &&
            isEmbedAt(before, at)) {
          ops.add(
            RichTextUpdateEmbed(
              embed,
              _changedAttributes(
                _withoutNull(richTextAttributes(_attributesAt(document, at))),
                attributes,
              ),
            ),
          );
          at++;
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
            _withoutNull(
              richTextAttributes(
                quillScopedAttributes(attributes, newline: newline),
              ),
            ),
          ),
        );
      });
      continue;
    }
    at += length;
    final attributes = op.attributes;
    final plain = attributes == null || attributes.isEmpty;
    var end = at > before.length ? before.length : at;
    if (RuneOffsets.splitsPair(before, end)) {
      end += plain && !op.isDelete ? -1 : 1;
    }
    final covered = before.substring(unit, end);
    unit = end;
    if (covered.isEmpty) {
      continue;
    }
    if (op.isDelete) {
      ops.add(RichTextDelete(RuneOffsets.length(covered)));
      continue;
    }
    if (plain) {
      ops.add(RichTextRetain(RuneOffsets.length(covered)));
      continue;
    }
    _forEachLine(covered, (piece, {required newline}) {
      ops.add(
        RichTextRetain(
          RuneOffsets.length(piece),
          richTextAttributes(
            quillScopedAttributes(attributes, newline: newline),
          ),
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
      final attributes = _withoutNull(
        quillAttributes(quillScopedAttributes(span.attributes, newline: false)),
      );
      result.insert(quillEmbed(embed), attributes.isEmpty ? null : attributes);
      continue;
    }
    _forEachLine(span.text, (piece, {required newline}) {
      final attributes = _withoutNull(
        quillAttributes(
          quillScopedAttributes(span.attributes, newline: newline),
        ),
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

/// Whether an embed sits at the code unit offset [at] of [plain], the plain
/// text of a Quill document.
bool isEmbedAt(String plain, int at) =>
    at < plain.length && plain.startsWith(RichTextSpan.objectReplacement, at);

/// The key of the source of an image or a video in a handler embed.
const String embedSrcKey = 'src';

/// The Quill embed type that holds a handler embed whole.
///
/// A Quill embed is a map of one key, its type. A `crdt_lf` image or video
/// with only `type` and `src` is the native Quill `{'image': src}` or
/// `{'video': src}`, and a native one comes back typed. Any other handler
/// embed, such as an image with an `alt`, goes to Quill as
/// `{crdtQuillEmbedType: embed}` and comes back as the same map.
/// `crdtQuillEmbedBuilders` gives the editor a builder for it, and
/// `crdtQuillUnknownEmbedBuilder` one for any other type.
const String crdtQuillEmbedType = 'crdt_lf';

/// The Quill embed for [embed], the data of a handler embed.
///
/// The shapes are the ones of [crdtQuillEmbedType].
Map<String, dynamic> quillEmbed(Map<String, Object?> embed) {
  final type = embed[richTextEmbedTypeKey];
  final src = embed[embedSrcKey];
  if (embed.length == 2 && _quillMedia.contains(type) && src is String) {
    return {type! as String: src};
  }
  if (embed.length != 1) {
    return {crdtQuillEmbedType: embed};
  }
  final MapEntry(:key, :value) = embed.entries.single;
  // A native image or video comes back as a typed one: wrap the plain one.
  return key == crdtQuillEmbedType || _isQuillMedia(key, value)
      ? {crdtQuillEmbedType: embed}
      : Map<String, dynamic>.of(embed);
}

/// The handler embed for [data], the insert of a Quill embed: an
/// [Embeddable] or its map.
///
/// A [crdtQuillEmbedType] embed gives back the map it wraps. Throws an
/// [ArgumentError] when [data] is neither, or a map has a key that is not a
/// `String`.
Map<String, Object?> richTextEmbed(Object? data) {
  final map = switch (data) {
    Embeddable() => {data.type: data.data},
    Map<dynamic, dynamic>() => _stringKeyed(data),
    _ => throw ArgumentError.value(data, 'data', 'is not a Quill embed'),
  };
  if (map.length == 1) {
    final MapEntry(:key, :value) = map.entries.single;
    if (key == crdtQuillEmbedType && value is Map<dynamic, dynamic>) {
      return _stringKeyed(value);
    }
    if (_isQuillMedia(key, value)) {
      return {richTextEmbedTypeKey: key, embedSrcKey: value};
    }
  }
  return Map<String, Object?>.of(map);
}

/// The handler attributes for [attributes], the attributes of Quill.
///
/// A px width in the `style` or `width` attribute is the
/// [richTextDisplayWidthKey] mark; the rest of `style` stays a `style` mark.
Map<String, Object?> richTextAttributes(Map<String, Object?> attributes) {
  final hasStyle = attributes.containsKey(_styleKey);
  if (!hasStyle && !attributes.containsKey(_widthKey)) {
    return attributes;
  }
  final style = attributes[_styleKey];
  final css = style is String ? _Css.parse(style) : null;
  final width = _pxWidth(attributes[_widthKey]);
  return {
    for (final entry in attributes.entries)
      if (entry.key != _styleKey && entry.key != _widthKey)
        entry.key: entry.value,
    if (hasStyle) _styleKey: css == null ? style : css.rest,
    if (attributes.containsKey(_widthKey) && width == null)
      _widthKey: attributes[_widthKey],
    richTextDisplayWidthKey: css?.width ?? width,
  };
}

/// The Quill attributes for [attributes], the attributes of the handler.
///
/// [richTextDisplayWidthKey] is the width in the `style` attribute. With
/// [current], the handler attributes the change applies to, a change of the
/// width or of the style keeps the other.
Map<String, Object?> quillAttributes(
  Map<String, Object?> attributes, {
  Map<String, Object?>? current,
}) {
  if (!_touchesSize(attributes)) {
    return attributes;
  }
  Object? pick(String key) =>
      attributes.containsKey(key) ? attributes[key] : current?[key];
  return {
    for (final entry in attributes.entries)
      if (entry.key != _styleKey && entry.key != richTextDisplayWidthKey)
        entry.key: entry.value,
    _styleKey: _quillStyle(pick(richTextDisplayWidthKey), pick(_styleKey)),
  };
}

Map<String, Object?> _stringKeyed(Map<dynamic, dynamic> map) {
  if (map.keys.any((key) => key is! String)) {
    throw ArgumentError.value(map, 'data', 'has a key that is not a String');
  }
  return Map<String, Object?>.of(map.cast<String, Object?>());
}

final String _styleKey = Attribute.style.key;
final String _widthKey = Attribute.width.key;
const Set<Object?> _quillMedia = {RichTextImage.type, RichTextVideo.type};

bool _isQuillMedia(Object? key, Object? value) =>
    _quillMedia.contains(key) && value is String;

bool _touchesSize(Map<String, Object?> attributes) =>
    attributes.containsKey(richTextDisplayWidthKey) ||
    attributes.containsKey(_styleKey);

// The `style` of Quill for the width [width] and the rest [rest].
String? _quillStyle(Object? width, Object? rest) {
  final valid = width is num && width.isFinite && width > 0;
  final declarations = [
    if (valid) '$_widthKey: ${_formatWidth(width)}',
    if (rest is String)
      for (final declaration in _Css.parse(rest).declarations)
        if (!valid || declaration.key != _widthKey) declaration.text,
  ];
  return declarations.isEmpty ? null : declarations.join('; ');
}

String _formatWidth(num width) =>
    width == width.roundToDouble() && width.abs() <= _maxSafeInt
    ? '${width.toInt()}'
    : '$width';

const int _maxSafeInt = 9007199254740991;

// A width in logical px, as Quill's builders read it, or `null`.
num? _pxWidth(Object? value) {
  final number = switch (value) {
    final num number => number.toDouble(),
    final String text => double.tryParse(
      text.trim().endsWith('px')
          ? text.trim().substring(0, text.trim().length - 2)
          : text.trim(),
    ),
    _ => null,
  };
  if (number == null || !number.isFinite || number <= 0) {
    return null;
  }
  return number == number.roundToDouble() && number <= _maxSafeInt
      ? number.toInt()
      : number;
}

// A CSS style string split as Quill's builders split it.
final class _Css {
  _Css._(this.declarations, this.width, this.rest);

  factory _Css.parse(String style) {
    final declarations = [
      for (final part in style.split(';'))
        if (part.trim().isNotEmpty)
          (key: part.split(':').first.trim(), text: part.trim()),
    ];
    // The last well formed width wins, as in Quill.
    String? value;
    for (final declaration in declarations) {
      final parts = declaration.text.split(':');
      if (declaration.key == _widthKey && parts.length == 2) {
        value = parts[1];
      }
    }
    final width = _pxWidth(value);
    final rest = [
      for (final declaration in declarations)
        if (width == null || declaration.key != _widthKey) declaration.text,
    ];
    return _Css._(declarations, width, rest.isEmpty ? null : rest.join('; '));
  }

  final List<({String key, String text})> declarations;

  // The px width, or `null`.
  final num? width;

  // The declarations but the px width; `null` when none.
  final String? rest;
}

// Visits the runs of [document] over [count] code units from [from], with
// their inline attributes.
void _forEachRun(
  Delta document,
  int from,
  int count,
  void Function(int length, Map<String, Object?> attributes) visit,
) {
  final end = from + count;
  var index = 0;
  var at = from;
  for (final op in document.toList()) {
    final next = index + (op.length ?? 0);
    if (next > at && at < end) {
      final length = (next < end ? next : end) - at;
      visit(
        length,
        quillScopedAttributes(op.attributes ?? const {}, newline: false),
      );
      at += length;
    }
    index = next;
  }
  if (at < end) {
    visit(end - at, const {});
  }
}

const int _newline = 0x0A;

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
