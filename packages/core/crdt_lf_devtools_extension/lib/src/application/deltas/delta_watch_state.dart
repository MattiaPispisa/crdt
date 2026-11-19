// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'delta_watch_cubit.dart';

/// The watched deltas of one handler.
class DeltaWatchState extends Equatable {
  const DeltaWatchState({
    this.handler,
    this.watching = false,
    this.deltas = const [],
    this.error,
  });

  /// The selected handler; `null` for none.
  final String? handler;

  final bool watching;

  /// Newest first.
  final List<HandlerDeltaEvent> deltas;

  /// The error of the last start or stop; `null` when it succeeded.
  final String? error;

  DeltaWatchState _copyWith({
    bool? watching,
    List<HandlerDeltaEvent>? deltas,
    String? Function()? error,
  }) => DeltaWatchState(
    handler: handler,
    watching: watching ?? this.watching,
    deltas: deltas ?? this.deltas,
    error: error == null ? this.error : error(),
  );

  @override
  List<Object?> get props => [handler, watching, deltas, error];
}
