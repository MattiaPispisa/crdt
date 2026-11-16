// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/handler_info.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:equatable/equatable.dart';

/// An open time travel session over [length] changes.
class HistorySessionInfo extends Equatable {
  const HistorySessionInfo({
    required this.session,
    required this.length,
    required this.versionVector,
    required this.handlers,
  });

  factory HistorySessionInfo.fromJson(Json json) => HistorySessionInfo(
    session: json.integer('session'),
    length: json.integer('length'),
    versionVector: json.stringMap('versionVector'),
    handlers: [
      for (final handler in json.objects('handlers'))
        HandlerInfo.fromJson(handler),
    ],
  );

  final int session;

  final int length;

  final Map<String, String> versionVector;

  final List<HandlerInfo> handlers;

  @override
  List<Object?> get props => [session, length, versionVector, handlers];
}
