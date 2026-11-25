// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/reload_gate.dart';
import 'package:equatable/equatable.dart';

part 'handlers_state.dart';

/// The handlers of the document [doc], and the selected one.
///
/// It reloads on a `document` event of [doc]. A burst of events shares one
/// load, made after `delay`. The selection is kept across reloads.
class HandlersCubit extends Cubit<HandlersState> {
  HandlersCubit(
    this._client,
    this.doc, {
    Duration delay = const Duration(milliseconds: 100),
  }) : super(const HandlersState()) {
    _gate = ReloadGate(_load, delay: delay);
    _events = _client.events.listen(_onEvent);
    unawaited(refresh());
  }

  final CrdtLfClient _client;

  /// The tracked id of the document.
  final int doc;

  late final ReloadGate _gate;

  late final StreamSubscription<CrdtLfEvent> _events;

  void _onEvent(CrdtLfEvent event) {
    if (event case DocumentMoved(
      :final doc,
      :final handlers,
      :final changes,
      :final snapshot,
      :final pruned,
    ) when doc == this.doc && (handlers || changes || snapshot || pruned)) {
      unawaited(refresh());
    }
  }

  /// Asks for a reload.
  Future<void> refresh() => _gate.request();

  /// Selects the handler [id]; `null` clears the selection.
  void select(String? id) {
    if (id == state.selectedId) return;
    emit(state._copyWith(selectedId: () => id));
  }

  Future<void> _load() async {
    try {
      final handlers = await _client.handlers(doc);
      if (isClosed) return;
      emit(
        HandlersState(
          status: LoadStatus.loaded,
          handlers: handlers,
          selectedId: state.selectedId,
        ),
      );
    } on Object catch (e) {
      if (isClosed) return;
      emit(state._copyWith(status: LoadStatus.failure, error: () => '$e'));
    }
  }

  @override
  Future<void> close() async {
    _gate.dispose();
    await _events.cancel();
    return super.close();
  }
}
