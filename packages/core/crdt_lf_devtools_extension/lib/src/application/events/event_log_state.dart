// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'event_log_cubit.dart';

/// The recorded events of a document.
class EventLogState extends Equatable {
  const EventLogState({
    this.recording = false,
    this.events = const [],
    this.selectedN,
    this.missed = false,
    this.error,
  });

  final bool recording;

  /// Newest first.
  final List<DocumentLogEvent> events;

  /// The `n` of the selected event; `null` for none.
  final int? selectedN;

  /// Whether the app stopped the log for a while since the recording
  /// started or was cleared: the events of that time are missing.
  final bool missed;

  /// The error of the last start or stop; `null` when it succeeded.
  final String? error;

  /// The selected event; `null` when none is selected or it was dropped.
  DocumentLogEvent? get selected {
    for (final event in events) {
      if (event.n == selectedN) return event;
    }
    return null;
  }

  EventLogState _copyWith({
    bool? recording,
    List<DocumentLogEvent>? events,
    int? Function()? selectedN,
    bool? missed,
    String? Function()? error,
  }) => EventLogState(
    recording: recording ?? this.recording,
    events: events ?? this.events,
    selectedN: selectedN == null ? this.selectedN : selectedN(),
    missed: missed ?? this.missed,
    error: error == null ? this.error : error(),
  );

  @override
  List<Object?> get props => [recording, events, selectedN, missed, error];
}
