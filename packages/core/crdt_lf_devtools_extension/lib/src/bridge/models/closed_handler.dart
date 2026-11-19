// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:equatable/equatable.dart';

/// A handler with data and no instance in the app; [type] is `null` when
/// the data does not say it.
class ClosedHandler extends Equatable {
  const ClosedHandler({
    required this.id,
    required this.type,
    required this.changeCount,
  });

  factory ClosedHandler.fromJson(Json json) => ClosedHandler(
    id: json.string('id'),
    type: json.stringOrNull('type'),
    changeCount: json.integer('changeCount'),
  );

  final String id;

  final String? type;

  final int changeCount;

  @override
  List<Object?> get props => [id, type, changeCount];
}
