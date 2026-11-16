// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/handler_info.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:equatable/equatable.dart';

/// The state of the cached value of a handler.
enum HandlerCache {
  /// Built and current.
  warm,

  /// Built for an older document state.
  stale,

  /// Not built.
  none,
}

/// An open handler of a document.
class HandlerSummary extends Equatable {
  const HandlerSummary({
    required this.id,
    required this.type,
    required this.container,
    required this.children,
    required this.changeCount,
    required this.revision,
    required this.cache,
    required this.pendingRemote,
    required this.deltas,
    required this.watched,
    required this.deltaSeq,
    required this.invertible,
    required this.undoTracked,
    required this.snapshotBytes,
  });

  factory HandlerSummary.fromJson(Json json) => HandlerSummary(
    id: json.string('id'),
    type: json.string('type'),
    container: json.boolean('container'),
    children: [
      for (final child in json.objects('children')) HandlerInfo.fromJson(child),
    ],
    changeCount: json.integer('changeCount'),
    revision: json.integer('revision'),
    cache: HandlerCache.values.byName(json.string('cache')),
    pendingRemote: json.integer('pendingRemote'),
    deltas: json.boolean('deltas'),
    watched: json.boolean('watched'),
    deltaSeq: json.integer('deltaSeq'),
    invertible: json.boolean('invertible'),
    undoTracked: json.boolean('undoTracked'),
    snapshotBytes: json.integerOrNull('snapshotBytes'),
  );

  final String id;

  final String type;

  final bool container;

  final List<HandlerInfo> children;

  final int changeCount;

  final int revision;

  final HandlerCache cache;

  final int pendingRemote;

  final bool deltas;

  final bool watched;

  final int deltaSeq;

  final bool invertible;

  final bool undoTracked;

  final int? snapshotBytes;

  @override
  List<Object?> get props => [
    id,
    type,
    container,
    children,
    changeCount,
    revision,
    cache,
    pendingRemote,
    deltas,
    watched,
    deltaSeq,
    invertible,
    undoTracked,
    snapshotBytes,
  ];
}
