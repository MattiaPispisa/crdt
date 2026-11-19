// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

typedef Json = Map<String, Object?>;

/// Typed reads of a protocol answer.
extension JsonRead on Json {
  int integer(String key) => this[key]! as int;

  int? integerOrNull(String key) => this[key] as int?;

  bool boolean(String key) => this[key]! as bool;

  bool? booleanOrNull(String key) => this[key] as bool?;

  String string(String key) => this[key]! as String;

  String? stringOrNull(String key) => this[key] as String?;

  Json object(String key) => (this[key]! as Map).cast<String, Object?>();

  Json? objectOrNull(String key) =>
      (this[key] as Map<Object?, Object?>?)?.cast<String, Object?>();

  List<Json> objects(String key) => [
    for (final item in this[key]! as List<Object?>)
      (item! as Map).cast<String, Object?>(),
  ];

  List<String> strings(String key) =>
      (this[key]! as List<Object?>).cast<String>().toList();

  Map<String, String> stringMap(String key) =>
      (this[key]! as Map).cast<String, String>();

  Map<String, String>? stringMapOrNull(String key) =>
      (this[key] as Map<Object?, Object?>?)?.cast<String, String>();
}
