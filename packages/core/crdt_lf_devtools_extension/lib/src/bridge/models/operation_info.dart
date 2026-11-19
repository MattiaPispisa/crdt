// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:equatable/equatable.dart';

/// The operation of a change; [payload] is `null` when the handler is not
/// open in the app.
class OperationInfo extends Equatable {
  const OperationInfo({
    required this.changeId,
    required this.handlerId,
    required this.handlerType,
    required this.kind,
    required this.stamped,
    required this.open,
    required this.payload,
    required this.error,
  });

  factory OperationInfo.fromJson(Json json) => OperationInfo(
    changeId: json.string('changeId'),
    handlerId: json.stringOrNull('handlerId'),
    handlerType: json.stringOrNull('handlerType'),
    kind: json.integerOrNull('kind'),
    stamped: json.booleanOrNull('stamped'),
    open: json.boolean('open'),
    payload: json['payload'],
    error: json.stringOrNull('error'),
  );

  final String changeId;

  final String? handlerId;

  final String? handlerType;

  final int? kind;

  final bool? stamped;

  final bool open;

  final Object? payload;

  final String? error;

  @override
  List<Object?> get props => [
    changeId,
    handlerId,
    handlerType,
    kind,
    stamped,
    open,
    payload,
    error,
  ];
}
