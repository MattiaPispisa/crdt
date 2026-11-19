// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:equatable/equatable.dart';

/// An undo manager of a document.
class UndoManagerSummary extends Equatable {
  const UndoManagerSummary({
    required this.canUndo,
    required this.canRedo,
    required this.undoDepth,
    required this.redoDepth,
    required this.tracked,
    required this.stackLimit,
    required this.captureTimeout,
    required this.trackedOrigins,
  });

  factory UndoManagerSummary.fromJson(Json json) => UndoManagerSummary(
    canUndo: json.boolean('canUndo'),
    canRedo: json.boolean('canRedo'),
    undoDepth: json.integer('undoDepth'),
    redoDepth: json.integer('redoDepth'),
    tracked: json.strings('tracked'),
    stackLimit: json.integer('stackLimit'),
    captureTimeout: Duration(milliseconds: json.integer('captureTimeoutMs')),
    trackedOrigins: json.integerOrNull('trackedOrigins'),
  );

  final bool canUndo;

  final bool canRedo;

  final int undoDepth;

  final int redoDepth;

  final List<String> tracked;

  final int stackLimit;

  final Duration captureTimeout;

  final int? trackedOrigins;

  @override
  List<Object?> get props => [
    canUndo,
    canRedo,
    undoDepth,
    redoDepth,
    tracked,
    stackLimit,
    captureTimeout,
    trackedOrigins,
  ];
}
