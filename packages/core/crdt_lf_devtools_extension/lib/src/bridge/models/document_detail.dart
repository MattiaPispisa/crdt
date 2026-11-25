// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/document_summary.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/undo_manager_summary.dart';
import 'package:equatable/equatable.dart';

/// A document with its undo managers and the formats this build reads.
class DocumentDetail extends Equatable {
  const DocumentDetail({
    required this.summary,
    required this.undo,
    required this.capabilities,
  });

  factory DocumentDetail.fromJson(Json json) => DocumentDetail(
    summary: DocumentSummary.fromJson(json),
    undo: [
      for (final manager in json.objects('undo'))
        UndoManagerSummary.fromJson(manager),
    ],
    capabilities: json.stringMap('capabilities'),
  );

  final DocumentSummary summary;

  final List<UndoManagerSummary> undo;

  final Map<String, String> capabilities;

  @override
  List<Object?> get props => [summary, undo, capabilities];
}
