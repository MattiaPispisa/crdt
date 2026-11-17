// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/reload_gate.dart';

part 'time_travel_state.dart';

/// A time travel session over the document [doc].
///
/// It opens the session when created and closes it when closed. The
/// session stays frozen: [TimeTravelState.newChanges] counts the changes
/// the live document got since, and [reopen] takes them in.
class TimeTravelCubit extends Cubit<TimeTravelState> {
  TimeTravelCubit(
    this._client,
    this.doc, {
    Duration delay = const Duration(milliseconds: 100),
    Duration valueDelay = const Duration(milliseconds: 50),
  }) : _mirror = ChangeMirror(_client, doc),
       super(const TimeTravelState()) {
    _openGate = ReloadGate(_open, delay: Duration.zero);
    _liveGate = ReloadGate(_syncLive, delay: delay);
    _valueGate = ReloadGate(_loadValue, delay: valueDelay);
    _events = _client.events.listen(_onEvent);
    unawaited(reopen());
  }

  final CrdtLfClient _client;

  /// The tracked id of the document.
  final int doc;

  final ChangeMirror _mirror;

  late final ReloadGate _openGate;

  late final ReloadGate _liveGate;

  late final ReloadGate _valueGate;

  late final StreamSubscription<CrdtLfEvent> _events;

  void _onEvent(CrdtLfEvent event) {
    if (event case DocumentMoved(
      :final doc,
      :final changes,
      :final pruned,
    ) when doc == this.doc && (changes || pruned)) {
      unawaited(_liveGate.request());
    }
  }

  /// Opens a new session on the live document, at its last change.
  Future<void> reopen() => _openGate.request();

  /// Moves the cursor to [cursor], clamped to the session.
  void moveTo(int cursor) {
    final next = cursor.clamp(0, state.length);
    if (next == state.cursor) return;
    emit(state._copyWith(cursor: next));
    unawaited(_valueGate.request());
  }

  /// Moves the cursor one change back.
  void previous() => moveTo(state.cursor - 1);

  /// Moves the cursor one change forward.
  void next() => moveTo(state.cursor + 1);

  /// Selects the [handler] of the session; `null` clears it.
  void select(String? handler) {
    if (handler == state.handler) return;
    emit(
      state._copyWith(
        handler: () => handler,
        valueStatus: LoadStatus.initial,
        value: () => null,
        valueError: () => null,
      ),
    );
    unawaited(_valueGate.request());
  }

  /// Loads the value at the cursor again.
  Future<void> reloadValue() => _valueGate.request();

  Future<void> _open() async {
    try {
      await _mirror.sync();
      final info = await _client.historyOpen(doc);
      if (isClosed) return await _closeSession(info.session);
      var frozen = _seenBy(info.versionVector);
      // A change can land between the sync and the open.
      if (frozen.length != info.length) {
        await _mirror.sync();
        if (isClosed) return await _closeSession(info.session);
        frozen = _seenBy(info.versionVector);
      }
      final handler = state.handler;
      final kept = info.handlers.any((h) => h.id == handler);
      emit(
        state._copyWith(
          status: LoadStatus.loaded,
          session: info,
          frozen: frozen,
          cursor: info.length,
          newChanges: _mirror.length - frozen.length,
          handler: kept ? null : () => null,
          valueStatus: LoadStatus.initial,
          value: () => null,
          valueError: () => null,
          error: () => null,
        ),
      );
      unawaited(_valueGate.request());
    } on Object catch (e) {
      if (isClosed) return;
      emit(state._copyWith(status: LoadStatus.failure, error: () => '$e'));
    }
  }

  Future<void> _syncLive() async {
    final session = state.session;
    if (session == null) return;
    try {
      await _mirror.sync();
    } on Object {
      // The count stays as it was; the next event syncs again.
      return;
    }
    if (isClosed || state.session != session) return;
    final seen = _seenBy(session.versionVector).length;
    emit(state._copyWith(newChanges: _mirror.length - seen));
  }

  Future<void> _loadValue() async {
    final session = state.session;
    final handler = state.handler;
    final cursor = state.cursor;
    if (session == null || handler == null) return;
    bool moved() =>
        isClosed ||
        state.session != session ||
        state.handler != handler ||
        state.cursor != cursor;
    try {
      final value = await _client.historyState(
        doc,
        session: session.session,
        cursor: cursor,
        handler: handler,
      );
      if (moved()) return;
      emit(
        state._copyWith(
          valueStatus: LoadStatus.loaded,
          value: () => value,
          valueError: () => null,
        ),
      );
    } on Object catch (e) {
      if (moved()) return;
      emit(
        state._copyWith(
          valueStatus: LoadStatus.failure,
          valueError: () => '$e',
        ),
      );
    }
  }

  List<MirrorEntry> _seenBy(Map<String, String> versionVector) {
    final clocks = {
      for (final MapEntry(:key, :value) in versionVector.entries)
        key: _parseClock(value),
    };
    return [
      for (final entry in _mirror.entries)
        if (clocks[entry.change.author.toString()] case (
          final l,
          final c,
        ) when _atOrBefore(entry.change.hlc.l, entry.change.hlc.c, l, c))
          entry,
    ];
  }

  static (int, int) _parseClock(String clock) {
    final dot = clock.indexOf('.');
    return (
      int.parse(clock.substring(0, dot)),
      int.parse(clock.substring(dot + 1)),
    );
  }

  static bool _atOrBefore(int l, int c, int maxL, int maxC) =>
      l < maxL || (l == maxL && c <= maxC);

  Future<void> _closeSession(int session) async {
    try {
      await _client.historyClose(doc, session);
    } on Object {
      // The document is gone, and its session with it.
    }
  }

  @override
  Future<void> close() async {
    _openGate.dispose();
    _liveGate.dispose();
    _valueGate.dispose();
    await _events.cancel();
    final session = state.session;
    await super.close();
    if (session != null) await _closeSession(session.session);
  }
}
