// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/reload_gate.dart';
import 'package:equatable/equatable.dart';

part 'storage_state.dart';

/// The storage of the document [doc]: its version, snapshot, formats and
/// undo managers.
///
/// It reloads on any `document` event of [doc]. A burst of events shares
/// one load, made after `delay`.
class StorageCubit extends Cubit<StorageState> {
  StorageCubit(
    this._client,
    this.doc, {
    Duration delay = const Duration(milliseconds: 100),
  }) : super(const StorageState()) {
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
    if (event is DocumentMoved && event.doc == doc) unawaited(refresh());
  }

  /// Asks for a reload.
  Future<void> refresh() => _gate.request();

  Future<void> _load() async {
    try {
      final detail = await _client.document(doc);
      final snapshot = await _client.snapshot(doc);
      if (isClosed) return;
      emit(
        StorageState(
          status: LoadStatus.loaded,
          detail: detail,
          snapshot: snapshot,
        ),
      );
    } on Object catch (e) {
      if (isClosed) return;
      emit(state._failed('$e'));
    }
  }

  @override
  Future<void> close() async {
    _gate.dispose();
    await _events.cancel();
    return super.close();
  }
}
