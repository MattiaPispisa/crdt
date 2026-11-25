// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:equatable/equatable.dart';

/// The id and type of a handler.
class HandlerInfo extends Equatable {
  const HandlerInfo({required this.id, required this.type});

  factory HandlerInfo.fromJson(Json json) =>
      HandlerInfo(id: json.string('id'), type: json.string('type'));

  final String id;

  final String type;

  @override
  List<Object?> get props => [id, type];
}
