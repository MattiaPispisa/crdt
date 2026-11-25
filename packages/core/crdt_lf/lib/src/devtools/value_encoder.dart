// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:crdt_lf/src/delta/rich_text_delta.dart';
import 'package:crdt_lf/src/handler/ref/handler_ref.dart';

/// The JSON-safe node of [value] that the DevTools extension draws.
///
/// A string longer than [maxString] code units, and a collection longer than
/// [maxItems], keep their head and their full length. A collection or object
/// [maxDepth] levels down becomes a `more` node.
Object? encodeDevToolsValue(
  Object? value, {
  int maxItems = 200,
  int maxString = 10000,
  int maxDepth = 8,
}) =>
    _ValueEncoder(maxItems, maxString, maxDepth).encode(value, 0);

final class _ValueEncoder {
  const _ValueEncoder(this.maxItems, this.maxString, this.maxDepth);

  final int maxItems;

  final int maxString;

  final int maxDepth;

  static const int _bytesHead = 32;

  Object? encode(Object? value, int depth) {
    switch (value) {
      // Before `int()`: on the web the infinities pass `is int`.
      case double(isFinite: false):
        return {r'$t': 'double', 'v': value.toString()};
      case null || bool() || num():
        return value;
      case String():
        if (value.length <= maxString) return value;
        return {
          r'$t': 'string',
          'length': value.length,
          'head': _cut(value),
        };
      case HandlerRef():
        return {r'$t': 'ref', 'id': value.id, 'type': value.type};
    }
    if (depth >= maxDepth) {
      return {r'$t': 'more'};
    }
    final next = depth + 1;
    switch (value) {
      case RichTextSpan():
        return {
          r'$t': 'span',
          'text': encode(value.text, next),
          'attributes': encode(value.attributes, next),
          'embed': encode(value.embed, next),
        };
      case Uint8List():
        final head = value.length <= _bytesHead
            ? value
            : Uint8List.sublistView(value, 0, _bytesHead);
        return {
          r'$t': 'bytes',
          'length': value.length,
          'head': [
            for (final byte in head) byte.toRadixString(16).padLeft(2, '0'),
          ].join(),
        };
      case Set<Object?>():
        return {
          r'$t': 'set',
          'length': value.length,
          'items': [
            for (final item in value.take(maxItems)) encode(item, next),
          ],
        };
      case Iterable<Object?>():
        return {
          r'$t': 'list',
          'length': value.length,
          'items': [
            for (final item in value.take(maxItems)) encode(item, next),
          ],
        };
      case Map<Object?, Object?>():
        return {
          r'$t': 'map',
          'length': value.length,
          'entries': [
            for (final entry in value.entries.take(maxItems))
              [encode(entry.key, next), encode(entry.value, next)],
          ],
        };
    }
    final text = value.toString();
    final json = _toJson(value);
    return {
      r'$t': 'object',
      'type': value.runtimeType.toString(),
      'text': text.length <= maxString ? text : _cut(text),
      if (json case (final Object? json,)) 'json': encode(json, next),
    };
  }

  String _cut(String text) {
    var end = maxString;
    if (end > 0 && _isHighSurrogate(text.codeUnitAt(end - 1))) {
      end--;
    }
    return text.substring(0, end);
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  static (Object?,)? _toJson(Object value) {
    try {
      // `toJson` is a convention, not an interface: only a dynamic call
      // finds it.
      // ignore: avoid_dynamic_calls
      return ((value as dynamic).toJson() as Object?,);
      // A missing `toJson` surfaces only as this error.
      // ignore: avoid_catching_errors
    } on NoSuchMethodError {
      return null;
    }
  }
}
