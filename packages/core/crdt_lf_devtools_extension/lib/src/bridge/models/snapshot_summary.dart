// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/snapshot_entry.dart';
import 'package:equatable/equatable.dart';

/// The last snapshot of a document.
///
/// [unfolded] and [requirements] are `null` when the app cannot read them.
class SnapshotSummary extends Equatable {
  const SnapshotSummary({
    required this.id,
    required this.versionVector,
    required this.bytes,
    required this.entries,
    required this.unfolded,
    required this.requirements,
  });

  factory SnapshotSummary.fromJson(Json json) => SnapshotSummary(
    id: json.string('id'),
    versionVector: json.stringMap('versionVector'),
    bytes: json.integer('bytes'),
    entries: [
      for (final entry in json.objects('entries'))
        SnapshotEntry.fromJson(entry),
    ],
    unfolded: json.objectOrNull('unfolded')?.cast<String, int?>(),
    requirements: json.stringMapOrNull('requirements'),
  );

  final String id;

  final Map<String, String> versionVector;

  final int bytes;

  final List<SnapshotEntry> entries;

  final Map<String, int?>? unfolded;

  final Map<String, String>? requirements;

  @override
  List<Object?> get props => [
    id,
    versionVector,
    bytes,
    entries,
    unfolded,
    requirements,
  ];
}
