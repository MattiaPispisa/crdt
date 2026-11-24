// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf_devtools_extension/src/application/lease_renewal.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
import 'package:equatable/equatable.dart';

part 'event_log_state.dart';

/// The event log of the document [doc], newest first.
///
/// Recording is off until [setRecording] turns it on. [close] stops it in
/// the app.
class EventLogCubit extends Cubit<EventLogState> {
  /// While recording, the cubit renews the lease of the log in the app
  /// every [renewEvery].
  EventLogCubit(
    this._client,
    this.doc, {
    Duration renewEvery = const Duration(seconds: 10),
  }) : super(const EventLogState()) {
    _renewal = LeaseRenewal(every: renewEvery, onMissed: _missed);
    // A log the app already runs stays: another DevTools window can own it.
    _events = _client.events.listen(_onEvent);
  }

  /// The events kept; the oldest go first.
  static const int maxEvents = 1000;

  final CrdtLfClient _client;

  /// The tracked id of the document.
  final int doc;

  late final StreamSubscription<CrdtLfEvent> _events;

  late final LeaseRenewal _renewal;

  // Set before the call: the app posts events before its answer arrives.
  bool _wanted = false;

  void _onEvent(CrdtLfEvent event) {
    if (!_wanted || event is! DocumentLogEvent || event.doc != doc) return;
    final events = [event, ...state.events.take(maxEvents - 1)];
    final kept = events.any((e) => e.n == state.selectedN);
    emit(state._copyWith(events: events, selectedN: kept ? null : () => null));
  }

  /// Starts or stops the event log in the app.
  ///
  /// A failed call keeps the previous state and sets the error.
  Future<void> setRecording({required bool recording}) async {
    _wanted = recording;
    // Before the stop: a renewal sent after it would start the log again.
    if (!recording) _renewal.stop();
    try {
      if (recording) {
        await _client.eventsStart(doc);
      } else {
        await _client.eventsStop(doc);
      }
      if (isClosed) return;
      if (recording) _renewal.start(_renew);
      emit(state._copyWith(recording: recording, error: () => null));
    } on Object catch (e) {
      if (isClosed) return;
      _wanted = state.recording;
      if (state.recording) _renewal.start(_renew);
      emit(state._copyWith(error: () => '$e'));
    }
  }

  /// Removes every event, and forgets the time the app stopped the log;
  /// recording goes on.
  void clear() => emit(
    state._copyWith(events: const [], selectedN: () => null, missed: false),
  );

  /// Selects the event number [n]; `null` clears the selection.
  void select(int? n) {
    if (n == state.selectedN) return;
    emit(state._copyWith(selectedN: () => n));
  }

  Future<bool> _renew() async => !_wanted || await _client.eventsStart(doc);

  // The lease ran out before a renewal: the app stopped the log.
  void _missed() {
    if (!isClosed && _wanted) emit(state._copyWith(missed: true));
  }

  Future<void> _stop() async {
    try {
      await _client.eventsStop(doc);
    } on Object {
      // The document can be gone: then the app already stopped the log.
    }
  }

  @override
  Future<void> close() async {
    _renewal.stop();
    if (_wanted) unawaited(_stop());
    await _events.cancel();
    return super.close();
  }
}
