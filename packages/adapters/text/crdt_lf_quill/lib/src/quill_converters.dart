// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_quill/src/quill_attributes.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';

Delta quillDeltaFromRichText(RichTextDelta delta, String before) {
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
    }
  }
  return result..trim();
}

RichTextDelta richTextDeltaFromQuill(Delta change, String before) {
  final ops = <RichTextOp>[];
  var unit = 0;
  for (final op in change.toList()) {
    final length = op.length ?? 0;
    if (op.isInsert) {
      final data = op.data;
      if (data is! String) {
        throw UnsupportedError('crdt_lf_quill does not support embeds');
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
      ops.add(RichTextDelete(RuneOffsets.length(covered)));
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

Delta quillDocumentFromSpans(List<RichTextSpan> spans) {
  final result = Delta();
  for (final span in spans) {
    _forEachLine(span.text, (piece, {required newline}) {
      final attributes = quillScopedAttributes(
        span.attributes,
        newline: newline,
      );
      result.insert(piece, attributes.isEmpty ? null : attributes);
    });
  }
  if (!trailingNewline(result).stored) {
    result.insert('\n');
  }
  return result;
}

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

const int _newline = 0x0A;

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
