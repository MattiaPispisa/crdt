// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:equatable/equatable.dart';

/// The value of a handler, as an encoded node tree.
class HandlerValue extends Equatable {
  const HandlerValue({
    required this.id,
    required this.type,
    required this.revision,
    required this.value,
  });

  factory HandlerValue.fromJson(Json json) => HandlerValue(
    id: json.string('id'),
    type: json.string('type'),
    revision: json.integer('revision'),
    value: json['value'],
  );

  final String id;

  final String type;

  final int revision;

  final Object? value;

  @override
  List<Object?> get props => [id, type, revision, value];
}
