// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:equatable/equatable.dart';

/// The state of a time travel session at [cursor].
class HistoryState extends Equatable {
  const HistoryState({
    required this.cursor,
    required this.frontiers,
    required this.value,
  });

  factory HistoryState.fromJson(Json json) => HistoryState(
    cursor: json.integer('cursor'),
    frontiers: json.strings('frontiers'),
    value: json['value'],
  );

  final int cursor;

  final List<String> frontiers;

  final Object? value;

  @override
  List<Object?> get props => [cursor, frontiers, value];
}
