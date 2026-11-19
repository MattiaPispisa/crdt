// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/reload_gate.dart';
import 'package:equatable/equatable.dart';

part 'handler_value_state.dart';

/// The value of the selected open handler of the document [doc].
///
/// It reloads on a `document` event of [doc] that moved its changes or its
/// snapshot. Each load builds the handler cache in the app, as a read by
/// the app does.
class HandlerValueCubit extends Cubit<HandlerValueState> {
  HandlerValueCubit(
    this._client,
    this.doc, {
    Duration delay = const Duration(milliseconds: 100),
  }) : super(const HandlerValueState()) {
    _gate = ReloadGate(_load, delay: delay);
    _events = _client.events.listen(_onEvent);
  }

  final CrdtLfClient _client;

  /// The tracked id of the document.
  final int doc;

  late final ReloadGate _gate;

  late final StreamSubscription<CrdtLfEvent> _events;

  void _onEvent(CrdtLfEvent event) {
    if (event case DocumentMoved(
      :final doc,
      :final changes,
      :final snapshot,
    ) when doc == this.doc && (changes || snapshot)) {
      unawaited(refresh());
    }
  }

  /// Reads the open [handler]; `null` clears the value.
  void select(String? handler) {
    if (handler == state.handler) return;
    emit(HandlerValueState(handler: handler));
    unawaited(refresh());
  }

  /// Asks for a reload of the selected value; a no-op with no selection.
  Future<void> refresh() =>
      state.handler == null ? Future.value() : _gate.request();

  Future<void> _load() async {
    final handler = state.handler;
    if (handler == null) return;
    try {
      final value = await _client.handlerValue(doc, handler);
      if (isClosed || state.handler != handler) return;
      emit(
        HandlerValueState(
          handler: handler,
          status: LoadStatus.loaded,
          value: value,
        ),
      );
    } on Object catch (e) {
      if (isClosed || state.handler != handler) return;
      emit(
        HandlerValueState(
          handler: handler,
          status: LoadStatus.failure,
          value: state.value,
          error: '$e',
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    _gate.dispose();
    await _events.cancel();
    return super.close();
  }
}
