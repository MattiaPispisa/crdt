// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'handler_value_cubit.dart';

/// The selected handler and its last loaded value.
class HandlerValueState extends Equatable {
  const HandlerValueState({
    this.handler,
    this.status = LoadStatus.initial,
    this.value,
    this.error,
  });

  /// The selected handler id; `null` when there is none.
  final String? handler;

  final LoadStatus status;

  /// The value of [handler]; `null` until its first load.
  final HandlerValue? value;

  /// The error of the last load; `null` unless [status] is a failure.
  final String? error;

  @override
  List<Object?> get props => [handler, status, value, error];
}
