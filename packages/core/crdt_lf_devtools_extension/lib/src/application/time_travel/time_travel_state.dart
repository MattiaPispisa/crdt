// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'time_travel_cubit.dart';

/// A time travel session, its cursor and the value of the selected handler
/// there.
// No value equality: comparing every change on each emit costs more than a
// rebuild.
class TimeTravelState {
  const TimeTravelState({
    this.status = LoadStatus.initial,
    this.progress,
    this.session,
    this.frozen = const [],
    this.cursor = 0,
    this.newChanges = 0,
    this.handler,
    this.valueStatus = LoadStatus.initial,
    this.value,
    this.valueError,
    this.error,
  });

  final LoadStatus status;

  /// The progress of the first change sync; `null` before its first page.
  final LoadProgress? progress;

  /// The open session; `null` until the first open ends.
  final HistorySessionInfo? session;

  /// The changes of [session], in replay order.
  final List<MirrorEntry> frozen;

  /// The number of changes applied, from 0 to the session length.
  final int cursor;

  /// The changes of the live document that [session] has not seen.
  final int newChanges;

  /// The selected handler id; `null` when there is none.
  final String? handler;

  /// The outcome of the last value load.
  final LoadStatus valueStatus;

  /// The state at [cursor]; `null` until it loads.
  final HistoryState? value;

  /// The error of the last value load; `null` unless it failed.
  final String? valueError;

  /// The error of the last open; `null` unless [status] is a failure.
  final String? error;

  /// The number of changes of [session].
  int get length => session?.length ?? 0;

  /// Whether [frozen] matches [session], so a change can be shown per
  /// cursor.
  bool get hasCards => frozen.length == length;

  /// The last change applied at [cursor]; `null` at 0 or without
  /// [hasCards].
  MirrorEntry? get current =>
      hasCards && cursor > 0 && cursor <= frozen.length
          ? frozen[cursor - 1]
          : null;

  TimeTravelState _copyWith({
    LoadStatus? status,
    LoadProgress? Function()? progress,
    HistorySessionInfo? session,
    List<MirrorEntry>? frozen,
    int? cursor,
    int? newChanges,
    String? Function()? handler,
    LoadStatus? valueStatus,
    HistoryState? Function()? value,
    String? Function()? valueError,
    String? Function()? error,
  }) => TimeTravelState(
    status: status ?? this.status,
    progress: progress == null ? this.progress : progress(),
    session: session ?? this.session,
    frozen: frozen ?? this.frozen,
    cursor: cursor ?? this.cursor,
    newChanges: newChanges ?? this.newChanges,
    handler: handler == null ? this.handler : handler(),
    valueStatus: valueStatus ?? this.valueStatus,
    value: value == null ? this.value : value(),
    valueError: valueError == null ? this.valueError : valueError(),
    error: error == null ? this.error : error(),
  );
}
