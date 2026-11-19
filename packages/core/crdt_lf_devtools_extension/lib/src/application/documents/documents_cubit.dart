// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/reload_gate.dart';
import 'package:equatable/equatable.dart';

part 'documents_state.dart';

/// Lists the documents of the app, and keeps the selection across
/// reloads.
///
/// It reloads when the protocol becomes available and on the `documents`
/// and `document` events. A burst of events shares one load, made after
/// `delay`.
class DocumentsCubit extends Cubit<DocumentsState> {
  DocumentsCubit(
    this._client, {
    Duration delay = const Duration(milliseconds: 100),
  }) : super(const DocumentsState()) {
    _gate = ReloadGate(_load, delay: delay);
    _events = _client.events.listen(_onEvent);
    _client.bridge.available.addListener(_onAvailable);
    _onAvailable();
  }

  final CrdtLfClient _client;

  late final ReloadGate _gate;

  late final StreamSubscription<CrdtLfEvent> _events;

  void _onEvent(CrdtLfEvent event) {
    if (event is DocumentsMoved || event is DocumentMoved) unawaited(refresh());
  }

  void _onAvailable() {
    if (_client.bridge.available.value) {
      unawaited(refresh());
    } else {
      emit(const DocumentsState());
    }
  }

  /// Asks for a reload.
  Future<void> refresh() => _gate.request();

  /// Selects the document [id]; an unknown id is ignored.
  void select(int id) {
    if (state.documents.every((d) => d.id != id)) return;
    emit(
      DocumentsState(
        status: state.status,
        documents: state.documents,
        selectedId: id,
        error: state.error,
      ),
    );
  }

  Future<void> _load() async {
    try {
      final documents = await _client.documents();
      if (isClosed) return;
      final kept = documents.any((d) => d.id == state.selectedId);
      emit(
        DocumentsState(
          status: DocumentsStatus.loaded,
          documents: documents,
          selectedId: kept ? state.selectedId : documents.firstOrNull?.id,
        ),
      );
    } on Object catch (e) {
      if (isClosed) return;
      emit(
        DocumentsState(
          status: DocumentsStatus.failure,
          documents: state.documents,
          selectedId: state.selectedId,
          error: '$e',
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    _gate.dispose();
    _client.bridge.available.removeListener(_onAvailable);
    await _events.cancel();
    return super.close();
  }
}
