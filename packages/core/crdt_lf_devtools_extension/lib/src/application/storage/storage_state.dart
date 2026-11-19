// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'storage_cubit.dart';

/// The `document` and `snapshot` answers of a document.
class StorageState extends Equatable {
  const StorageState({
    this.status = LoadStatus.initial,
    this.detail,
    this.snapshot,
    this.error,
  });

  final LoadStatus status;

  /// The last loaded document; `null` before the first load.
  final DocumentDetail? detail;

  /// The last loaded snapshot answer; `null` before the first load.
  final SnapshotInfo? snapshot;

  /// The error of the last load; `null` unless [status] is a failure.
  final String? error;

  /// The snapshot entries, largest first.
  List<SnapshotEntry> get entriesBySize =>
      [...?snapshot?.snapshot?.entries]
        ..sort((a, b) => b.bytes.compareTo(a.bytes));

  /// The formats the data needs, by handler type.
  ///
  /// The live ones when the app tracks them, else the ones of the snapshot;
  /// `null` when neither is known.
  Map<String, String>? get requirements =>
      snapshot?.liveRequirements ?? snapshot?.snapshot?.requirements;

  /// One row per handler type that this build reads or the data needs.
  List<FormatRow> get formats {
    final reads = detail?.capabilities ?? const {};
    final needs = requirements ?? const {};
    final types = {...reads.keys, ...needs.keys}.toList()..sort();
    return [
      for (final type in types)
        FormatRow(type: type, reads: reads[type], needs: needs[type]),
    ];
  }

  StorageState _failed(String error) => StorageState(
    status: LoadStatus.failure,
    detail: detail,
    snapshot: snapshot,
    error: error,
  );

  @override
  List<Object?> get props => [status, detail, snapshot, error];
}

/// The formats of one handler type.
class FormatRow extends Equatable {
  const FormatRow({required this.type, this.reads, this.needs});

  /// The handler type.
  final String type;

  /// The formats this build reads; `null` when it does not list [type].
  final String? reads;

  /// The formats the data needs; `null` when it needs none.
  final String? needs;

  /// Whether the data needs [type] and this build does not list it.
  bool get missing => needs != null && reads == null;

  @override
  List<Object?> get props => [type, reads, needs];
}
