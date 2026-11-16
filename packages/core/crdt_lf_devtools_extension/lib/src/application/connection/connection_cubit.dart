// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:bloc/bloc.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_bridge.dart';
import 'package:equatable/equatable.dart';

part 'connection_status.dart';

/// Follows the link with the app: [CrdtLfBridge.connected],
/// [CrdtLfBridge.available] and [CrdtLfBridge.paused].
class ConnectionCubit extends Cubit<ConnectionStatus> {
  ConnectionCubit(this._bridge) : super(_read(_bridge)) {
    _bridge.connected.addListener(_update);
    _bridge.available.addListener(_update);
    _bridge.paused.addListener(_update);
  }

  final CrdtLfBridge _bridge;

  static ConnectionStatus _read(CrdtLfBridge bridge) => ConnectionStatus(
    connected: bridge.connected.value,
    available: bridge.available.value,
    paused: bridge.paused.value,
  );

  void _update() => emit(_read(_bridge));

  @override
  Future<void> close() {
    _bridge.connected.removeListener(_update);
    _bridge.available.removeListener(_update);
    _bridge.paused.removeListener(_update);
    return super.close();
  }
}
