// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:equatable/equatable.dart';

/// A live document of the app, as `documents` lists it.
class DocumentSummary extends Equatable {
  const DocumentSummary({
    required this.id,
    required this.documentId,
    required this.peerId,
    required this.debugName,
    required this.handlerNames,
    required this.hlc,
    required this.changeCount,
    required this.handlerCount,
    required this.frontiers,
    required this.versionVector,
    required this.snapshotId,
    required this.pruneEpoch,
    required this.undoManagers,
    required this.recording,
  });

  factory DocumentSummary.fromJson(Json json) => DocumentSummary(
    id: json.integer('id'),
    documentId: json.string('documentId'),
    peerId: json.string('peerId'),
    debugName: json.stringOrNull('debugName'),
    handlerNames: json.stringMap('handlerNames'),
    hlc: json.string('hlc'),
    changeCount: json.integer('changeCount'),
    handlerCount: json.integer('handlerCount'),
    frontiers: json.strings('frontiers'),
    versionVector: json.stringMap('versionVector'),
    snapshotId: json.stringOrNull('snapshotId'),
    pruneEpoch: json.integer('pruneEpoch'),
    undoManagers: json.integer('undoManagers'),
    recording: json.boolean('recording'),
  );

  final int id;

  final String documentId;

  final String peerId;

  /// `null` for none.
  final String? debugName;

  /// The debug names of the handlers, by id.
  final Map<String, String> handlerNames;

  final String hlc;

  final int changeCount;

  final int handlerCount;

  final List<String> frontiers;

  final Map<String, String> versionVector;

  final String? snapshotId;

  final int pruneEpoch;

  final int undoManagers;

  final bool recording;

  @override
  List<Object?> get props => [
    id,
    documentId,
    peerId,
    debugName,
    handlerNames,
    hlc,
    changeCount,
    handlerCount,
    frontiers,
    versionVector,
    snapshotId,
    pruneEpoch,
    undoManagers,
    recording,
  ];
}
