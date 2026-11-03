// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:crdt_lf/src/utils/bytes.dart';

final Expando<bool> _frozen = Expando('frozen embed');

/// A deep, unmodifiable copy of [embed], keys in the same order.
Map<String, Object?> freezeEmbed(Map<String, Object?> embed) {
  if (_frozen[embed] ?? false) {
    return embed;
  }
  final copy = Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final entry in embed.entries) entry.key: _freezeValue(entry.value),
  });
  _frozen[copy] = true;
  return copy;
}

Object? _freezeValue(Object? value) {
  switch (value) {
    case final Uint8List bytes:
      return Uint8List.fromList(bytes).asUnmodifiableView();
    case final List<Object?> list:
      return List<Object?>.unmodifiable(list.map(_freezeValue));
    case final Map<Object?, Object?> map:
      return freezeEmbed(<String, Object?>{
        for (final entry in map.entries) _key(entry.key): entry.value,
      });
    default:
      return value;
  }
}

String _key(Object? key) {
  if (key is String) {
    return key;
  }
  throw ArgumentError.value(key, 'embed', 'map keys must be strings');
}

/// Whether [a] and [b] hold the same data, map keys in any order.
bool sameEmbed(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is Uint8List || b is Uint8List) {
    return a is Uint8List && b is Uint8List && bytesEqual(a, b);
  }
  if (a is List<Object?>) {
    if (b is! List<Object?> || a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!sameEmbed(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is Map<Object?, Object?>) {
    if (b is! Map<Object?, Object?> || a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || !sameEmbed(entry.value, b[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

/// A hash code that agrees with [sameEmbed].
int hashEmbed(Object? value) {
  switch (value) {
    case final Uint8List bytes:
      return Object.hashAll(bytes);
    case final List<Object?> list:
      return Object.hashAll(list.map(hashEmbed));
    case final Map<Object?, Object?> map:
      return Object.hashAllUnordered(
        map.entries
            .map((entry) => Object.hash(entry.key, hashEmbed(entry.value))),
      );
    default:
      return value.hashCode;
  }
}
