// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/reload_gate.dart';

part 'time_travel_state.dart';

/// A time travel session over the document of a [ChangeMirror].
///
/// It opens the session when created and closes it when closed. The
/// session stays frozen: [TimeTravelState.newChanges] counts the changes
/// the live document got since, and [reopen] takes them in. When the app
/// ends the session, the cubit opens a new one at the same cursor.
class TimeTravelCubit extends Cubit<TimeTravelState> {
  /// While a session is open, the cubit renews its lease in the app every
  /// [renewEvery].
  TimeTravelCubit(
    this._mirror, {
    Duration delay = const Duration(milliseconds: 100),
    Duration valueDelay = const Duration(milliseconds: 50),
    Duration renewEvery = const Duration(seconds: 10),
  }) : _renewEvery = renewEvery,
       super(const TimeTravelState()) {
    _openGate = ReloadGate(_open, delay: Duration.zero);
    _liveGate = ReloadGate(_syncLive, delay: delay);
    _valueGate = ReloadGate(_loadValue, delay: valueDelay);
    _events = _client.events.listen(_onEvent);
    unawaited(reopen());
  }

  /// The error shown when another DevTools window opened time travel on the
  /// document.
  static const String taken =
      'Another DevTools window opened time travel on this document.';

  final ChangeMirror _mirror;

  CrdtLfClient get _client => _mirror.client;

  /// The tracked id of the document.
  int get doc => _mirror.doc;

  late final ReloadGate _openGate;

  late final ReloadGate _liveGate;

  late final ReloadGate _valueGate;

  late final StreamSubscription<CrdtLfEvent> _events;

  final Duration _renewEvery;

  Timer? _renewal;

  // How many mirror entries the session holds, as of `_mark`.
  int _seen = 0;

  MirrorMark? _mark;

  // Whether the next session opens at the cursor, not at its last change.
  bool _keepCursor = false;

  // While a session opens, a call on the one it replaces fails on purpose.
  bool _opening = false;

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
    final keepCursor = _keepCursor;
    _keepCursor = false;
    _opening = true;
    HistorySessionInfo? opened;
    try {
      await _mirror.sync(
        onProgress: state.session == null ? _onProgress : null,
      );
      if (isClosed) return;
      final info = opened = await _client.historyOpen(doc);
      if (isClosed) return await _closeSession(info.session);
      var read = _mirror.read();
      var frozen = _seenBy(read.entries, info.versionVector);
      // A change can land between the sync and the open.
      if (frozen.length != info.length) {
        await _mirror.sync();
        if (isClosed) return await _closeSession(info.session);
        read = _mirror.read();
        frozen = _seenBy(read.entries, info.versionVector);
      }
      _mark = read.mark;
      _seen = frozen.length;
      final handler = state.handler;
      final kept = info.handlers.any((h) => h.id == handler);
      emit(
        state._copyWith(
          status: LoadStatus.loaded,
          session: info,
          frozen: frozen,
          // The cursor now: the user can move it while the session opens.
          cursor: keepCursor ? state.cursor.clamp(0, info.length) : info.length,
          newChanges: _mirror.length - frozen.length,
          handler: kept ? null : () => null,
          valueStatus: LoadStatus.initial,
          value: () => null,
          valueError: () => null,
          error: () => null,
        ),
      );
      _renewal?.cancel();
      _renewal = Timer.periodic(_renewEvery, (_) => unawaited(_renew()));
      unawaited(_valueGate.request());
    } on Object catch (e) {
      if (isClosed) return;
      if (opened == null) {
        emit(state._copyWith(status: LoadStatus.failure, error: () => '$e'));
        return;
      }
      // The new session replaced the one the state shows: drop both.
      unawaited(_closeSession(opened.session));
      _renewal?.cancel();
      emit(
        const TimeTravelState()._copyWith(
          status: LoadStatus.failure,
          error: () => '$e',
        ),
      );
    } finally {
      _opening = false;
    }
  }

  Future<void> _renew() async {
    final session = state.session;
    if (session == null) return;
    try {
      await _client.historyState(
        doc,
        session: session.session,
        cursor: state.cursor,
      );
    } on HistorySessionClosed catch (e) {
      _resume(session, e);
    } on Object {
      // The next tick tries again.
    }
  }

  // A lease that ran out (a paused app, a throttled tab) ends the session.
  // A newer session, open or opening, already replaced [ended].
  void _resume(HistorySessionInfo ended, HistorySessionClosed error) {
    if (isClosed || _opening || state.session != ended) return;
    // Another DevTools window took the session: taking it back at once
    // would end the other one's, and so on.
    if (error is HistorySessionReplaced) {
      _renewal?.cancel();
      emit(
        const TimeTravelState()._copyWith(
          status: LoadStatus.failure,
          error: () => taken,
        ),
      );
      return;
    }
    _keepCursor = true;
    unawaited(reopen());
  }

  void _onProgress(int loaded, int total) {
    if (isClosed || state.session != null) return;
    emit(state._copyWith(progress: () => (loaded: loaded, total: total)));
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
    final read = _mirror.read(_mark);
    _mark = read.mark;
    // A peer's changes arrive in causal order, so an entry new to the
    // mirror is newer than the session: only a full read counts again.
    if (read.from == 0) {
      _seen = _seenBy(read.entries, session.versionVector).length;
    }
    emit(state._copyWith(newChanges: _mirror.length - _seen));
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
    } on HistorySessionClosed catch (e) {
      _resume(session, e);
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

  static List<MirrorEntry> _seenBy(
    List<MirrorEntry> entries,
    Map<String, String> versionVector,
  ) {
    final clocks = {
      for (final MapEntry(:key, :value) in versionVector.entries)
        key: _parseClock(value),
    };
    return [
      for (final entry in entries)
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
    _renewal?.cancel();
    _openGate.dispose();
    _liveGate.dispose();
    _valueGate.dispose();
    await _events.cancel();
    final session = state.session;
    await super.close();
    if (session != null) await _closeSession(session.session);
  }
}
