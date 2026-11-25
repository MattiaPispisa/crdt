// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:equatable/equatable.dart';

/// An event posted by the app, with its time of arrival.
class BridgeEvent extends Equatable {
  const BridgeEvent({
    required this.kind,
    required this.data,
    required this.time,
  });

  final String kind;

  final Json data;

  final DateTime time;

  @override
  List<Object?> get props => [kind, data, time];
}
