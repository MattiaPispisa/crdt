// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'connection_cubit.dart';

/// The link with the app, as [ConnectionCubit] reads it.
class ConnectionStatus extends Equatable {
  const ConnectionStatus({
    required this.connected,
    required this.available,
    required this.paused,
  });

  final bool connected;

  final bool available;

  final bool paused;

  @override
  List<Object?> get props => [connected, available, paused];
}
