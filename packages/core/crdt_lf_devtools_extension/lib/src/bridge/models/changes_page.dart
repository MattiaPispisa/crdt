// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:equatable/equatable.dart';

/// A page of changes, as `Change.toBytes` bytes; [done] is `false` when
/// more changes follow.
class ChangesPage extends Equatable {
  const ChangesPage({
    required this.pruneEpoch,
    required this.changeCount,
    required this.done,
    required this.changes,
  });

  factory ChangesPage.fromJson(Json json) => ChangesPage(
    pruneEpoch: json.integer('pruneEpoch'),
    changeCount: json.integer('changeCount'),
    done: json.boolean('done'),
    changes: [
      for (final change in json.strings('changes')) base64Decode(change),
    ],
  );

  final int pruneEpoch;

  final int changeCount;

  final bool done;

  final List<Uint8List> changes;

  @override
  List<Object?> get props => [pruneEpoch, changeCount, done, changes];
}
