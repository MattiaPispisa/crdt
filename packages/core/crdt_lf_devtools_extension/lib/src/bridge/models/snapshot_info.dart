// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/snapshot_summary.dart';
import 'package:equatable/equatable.dart';

/// The snapshot of a document; [snapshot] is `null` before the first one.
class SnapshotInfo extends Equatable {
  const SnapshotInfo({
    required this.snapshot,
    required this.deleted,
    required this.liveRequirements,
  });

  factory SnapshotInfo.fromJson(Json json) {
    final snapshot = json.objectOrNull('snapshot');
    return SnapshotInfo(
      snapshot: snapshot == null ? null : SnapshotSummary.fromJson(snapshot),
      deleted: json.strings('deleted'),
      liveRequirements: json.stringMapOrNull('liveRequirements'),
    );
  }

  final SnapshotSummary? snapshot;

  final List<String> deleted;

  final Map<String, String>? liveRequirements;

  @override
  List<Object?> get props => [snapshot, deleted, liveRequirements];
}
