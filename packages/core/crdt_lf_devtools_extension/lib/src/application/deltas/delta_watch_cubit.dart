// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
import 'package:equatable/equatable.dart';

part 'delta_watch_state.dart';

/// The deltas of the selected handler of the document [doc], newest
/// first.
///
/// Watching is off until [setWatching] turns it on. A new selection and
/// [close] stop the watch in the app.
class DeltaWatchCubit extends Cubit<DeltaWatchState> {
  /// While watching, the cubit renews the lease of the watch in the app
  /// every [renewEvery].
  DeltaWatchCubit(
    this._client,
    this.doc, {
    Duration renewEvery = const Duration(seconds: 10),
  }) : _renewEvery = renewEvery,
       super(const DeltaWatchState()) {
    _events = _client.events.listen(_onEvent);
  }

  /// The deltas kept; the oldest go first.
  static const int maxDeltas = 500;

  final CrdtLfClient _client;

  /// The tracked id of the document.
  final int doc;

  late final StreamSubscription<CrdtLfEvent> _events;

  final Duration _renewEvery;

  Timer? _renewal;

  // Set before the call: the app posts the initial reset before its answer
  // arrives.
  String? _wanted;

  // Moves on each start, stop and selection: an answer to an older one is
  // stale.
  int _request = 0;

  void _onEvent(CrdtLfEvent event) {
    if (event is! HandlerDeltaEvent ||
        event.doc != doc ||
        event.handler != _wanted ||
        event.handler != state.handler) {
      return;
    }
    emit(state._copyWith(deltas: [event, ...state.deltas.take(maxDeltas - 1)]));
  }

  /// Selects [handler] and clears the deltas; `null` for a handler with
  /// no deltas.
  void select(String? handler) {
    if (handler == state.handler) return;
    _request++;
    final watched = _wanted;
    if (watched != null) unawaited(_stop(watched));
    _wanted = null;
    _renewWhile(null);
    emit(DeltaWatchState(handler: handler));
  }

  /// Starts or stops the watch of the selected handler; a no-op with no
  /// selection.
  ///
  /// A failed call keeps the previous state and sets the error.
  Future<void> setWatching({required bool watching}) async {
    final handler = state.handler;
    if (handler == null) return;
    final request = ++_request;
    _wanted = watching ? handler : null;
    try {
      if (watching) {
        await _client.watchStart(doc, handler);
      } else {
        await _client.watchStop(doc, handler);
      }
      if (isClosed || request != _request) return;
      _renewWhile(watching ? handler : null);
      emit(state._copyWith(watching: watching, error: () => null));
    } on Object catch (e) {
      if (isClosed || request != _request) return;
      _wanted = state.watching ? handler : null;
      emit(state._copyWith(error: () => '$e'));
    }
  }

  void _renewWhile(String? handler) {
    _renewal?.cancel();
    _renewal =
        handler == null
            ? null
            : Timer.periodic(_renewEvery, (_) => unawaited(_renew(handler)));
  }

  Future<void> _renew(String handler) async {
    try {
      final renewed = await _client.watchStart(doc, handler);
      // The lease ran out before this renewal: the app stopped the watch.
      if (!renewed && !isClosed && _wanted == handler) {
        emit(state._copyWith(missed: true));
      }
    } on Object {
      // The next tick tries again.
    }
  }

  Future<void> _stop(String handler) async {
    try {
      await _client.watchStop(doc, handler);
    } on Object {
      // The document can be gone: then the app already stopped the watch.
    }
  }

  @override
  Future<void> close() async {
    _renewal?.cancel();
    final watched = _wanted;
    if (watched != null) unawaited(_stop(watched));
    await _events.cancel();
    return super.close();
  }
}
