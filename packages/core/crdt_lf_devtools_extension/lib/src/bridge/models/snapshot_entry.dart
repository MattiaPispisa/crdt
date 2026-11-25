// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:equatable/equatable.dart';

/// One record of a snapshot.
class SnapshotEntry extends Equatable {
  const SnapshotEntry({
    required this.key,
    required this.bytes,
    required this.reserved,
    required this.type,
  });

  factory SnapshotEntry.fromJson(Json json) => SnapshotEntry(
    key: json.string('key'),
    bytes: json.integer('bytes'),
    reserved: json.boolean('reserved'),
    type: json.stringOrNull('type'),
  );

  final String key;

  final int bytes;

  final bool reserved;

  final String? type;

  @override
  List<Object?> get props => [key, bytes, reserved, type];
}
