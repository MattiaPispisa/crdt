// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'delta_watch_cubit.dart';

/// The watched deltas of one handler.
class DeltaWatchState extends Equatable {
  const DeltaWatchState({
    this.handler,
    this.watching = false,
    this.deltas = const [],
    this.missed = false,
    this.error,
  });

  /// The selected handler; `null` for none.
  final String? handler;

  final bool watching;

  /// Newest first.
  final List<HandlerDeltaEvent> deltas;

  /// Whether the app stopped the watch for a while since it started: the
  /// deltas of that time are missing.
  final bool missed;

  /// The error of the last start or stop; `null` when it succeeded.
  final String? error;

  DeltaWatchState _copyWith({
    bool? watching,
    List<HandlerDeltaEvent>? deltas,
    bool? missed,
    String? Function()? error,
  }) => DeltaWatchState(
    handler: handler,
    watching: watching ?? this.watching,
    deltas: deltas ?? this.deltas,
    missed: missed ?? this.missed,
    error: error == null ? this.error : error(),
  );

  @override
  List<Object?> get props => [handler, watching, deltas, missed, error];
}
