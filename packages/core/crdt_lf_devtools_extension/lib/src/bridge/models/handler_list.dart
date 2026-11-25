// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/closed_handler.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/handler_summary.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:equatable/equatable.dart';

/// The open, closed and deleted handlers of a document.
class HandlerList extends Equatable {
  const HandlerList({
    required this.open,
    required this.closed,
    required this.deleted,
  });

  factory HandlerList.fromJson(Json json) => HandlerList(
    open: [
      for (final handler in json.objects('open'))
        HandlerSummary.fromJson(handler),
    ],
    closed: [
      for (final handler in json.objects('closed'))
        ClosedHandler.fromJson(handler),
    ],
    deleted: json.strings('deleted'),
  );

  final List<HandlerSummary> open;

  final List<ClosedHandler> closed;

  final List<String> deleted;

  @override
  List<Object?> get props => [open, closed, deleted];
}
