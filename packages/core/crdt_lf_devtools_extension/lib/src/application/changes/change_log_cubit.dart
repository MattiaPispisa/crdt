// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/application/changes/list_views.dart';
import 'package:crdt_lf_devtools_extension/src/application/changes/row_graph.dart';
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/reload_gate.dart';
import 'package:equatable/equatable.dart';

part 'change_log_state.dart';

/// The changes of the document of a [ChangeMirror].
///
/// It syncs on a `document` event of the document that moved its changes or
/// pruned them. A burst of events shares one sync, made after `delay`.
/// The selection is kept across syncs while the change is loaded.
class ChangeLogCubit extends Cubit<ChangeLogState> {
  /// Starts with the change [selected]; the first sync drops it when the
  /// mirror lacks it.
  ChangeLogCubit(
    this._mirror, {
    OperationId? selected,
    Duration delay = const Duration(milliseconds: 100),
  }) : _matched = <MirrorEntry>[],
       super(ChangeLogState(selectedId: selected)) {
    _gate = ReloadGate(_load, delay: delay);
    _events = _client.events.listen(_onEvent);
    unawaited(refresh());
  }

  final ChangeMirror _mirror;

  CrdtLfClient get _client => _mirror.client;

  /// The tracked id of the document.
  int get doc => _mirror.doc;

  late final ReloadGate _gate;

  late final StreamSubscription<CrdtLfEvent> _events;

  // Where `state.index` stopped reading the mirror.
  MirrorMark? _mark;

  // The changes of `_matchedIndex` that pass `_matchedFilter`. Like the
  // index tables, a sync changes it in place for the last state.
  List<MirrorEntry> _matched;

  ChangeIndex _matchedIndex = ChangeIndex.empty;

  ChangeFilter? _matchedFilter;

  void _onEvent(CrdtLfEvent event) {
    if (event case DocumentMoved(
      :final doc,
      :final changes,
      :final pruned,
    ) when doc == this.doc && (changes || pruned)) {
      unawaited(refresh());
    }
  }

  /// Asks for a sync.
  Future<void> refresh() => _gate.request();

  /// Shows only the changes that pass [filter].
  void setFilter(ChangeFilter filter) {
    if (filter == state.filter) return;
    emit(
      state._copyWith(
        filter: filter,
        visible: _visible(state.index, filter, state.newestFirst),
      ),
    );
  }

  /// Orders the list newest first, or in replay order.
  void setNewestFirst({required bool newestFirst}) {
    if (newestFirst == state.newestFirst) return;
    emit(
      state._copyWith(
        newestFirst: newestFirst,
        visible: _visible(state.index, state.filter, newestFirst),
      ),
    );
  }

  /// Selects the change [id] and loads its operation; `null` clears it.
  void select(OperationId? id) {
    if (id == state.selectedId) return;
    emit(
      state._copyWith(
        selectedId: () => id,
        operationStatus: LoadStatus.initial,
        operation: () => null,
        operationError: () => null,
      ),
    );
    unawaited(reloadOperation());
  }

  /// Loads the operation of the selected change again.
  Future<void> reloadOperation() async {
    final entry = state.selected;
    if (entry == null) return;
    final id = entry.change.id;
    try {
      final operation = await _client.operation(doc, entry.bytes);
      if (isClosed || state.selectedId != id) return;
      emit(
        state._copyWith(
          operationStatus: LoadStatus.loaded,
          operation: () => operation,
          operationError: () => null,
        ),
      );
    } on Object catch (e) {
      if (isClosed || state.selectedId != id) return;
      emit(
        state._copyWith(
          operationStatus: LoadStatus.failure,
          operationError: () => '$e',
        ),
      );
    }
  }

  Future<void> _load() async {
    try {
      await _mirror.sync(
        onProgress: state.status == LoadStatus.initial ? _onProgress : null,
      );
      if (isClosed) return;
      final read = _mirror.read(_mark);
      _mark = read.mark;
      // Before `replaceFrom`, which changes the tables the old index reads.
      final wasLoaded = state.selected != null;
      final previous = state.index;
      final index = previous.replaceFrom(read.from, read.entries);
      final selectedId = state.selectedId;
      final kept = selectedId != null && index.entryOf(selectedId) != null;
      final pending = kept && !wasLoaded;
      emit(
        state._copyWith(
          status: LoadStatus.loaded,
          index: index,
          visible: _visible(
            index,
            state.filter,
            state.newestFirst,
            previous: previous,
            keep: read.from,
          ),
          selectedId: kept ? null : () => null,
          operationStatus: kept ? null : LoadStatus.initial,
          operation: kept ? null : () => null,
          operationError: kept ? null : () => null,
          error: () => null,
        ),
      );
      if (pending) unawaited(reloadOperation());
    } on Object catch (e) {
      if (isClosed) return;
      emit(state._copyWith(status: LoadStatus.failure, error: () => '$e'));
    }
  }

  void _onProgress(int loaded, int total) {
    if (isClosed || state.status != LoadStatus.initial) return;
    emit(state._copyWith(progress: () => (loaded: loaded, total: total)));
  }

  // [keep]: how many entries [index] took from [previous], the index of the
  // state before; with no [previous], [index] is that index.
  List<MirrorEntry> _visible(
    ChangeIndex index,
    ChangeFilter filter,
    bool newestFirst, {
    ChangeIndex? previous,
    int? keep,
  }) {
    final entries =
        filter.isEmpty
            ? index.entries
            : _matching(
              index,
              filter,
              previous ?? index,
              keep ?? index.entries.length,
            );
    return newestFirst ? ReversedView(entries) : entries;
  }

  List<MirrorEntry> _matching(
    ChangeIndex index,
    ChangeFilter filter,
    ChangeIndex previous,
    int keep,
  ) {
    var from = 0;
    // The cache follows the index only while each state builds it.
    if (filter == _matchedFilter && identical(_matchedIndex, previous)) {
      from = min(keep, previous.entries.length);
      final positions = index._tables?.positions ?? const {};
      while (_matched.isNotEmpty &&
          (positions[_matched.last.change.id] ?? from) >= from) {
        _matched.removeLast();
      }
    } else {
      _matched = <MirrorEntry>[];
    }
    final entries = index.entries;
    final matches = filter.matcher();
    for (var i = from; i < entries.length; i++) {
      if (matches(entries[i])) _matched.add(entries[i]);
    }
    _matchedIndex = index;
    _matchedFilter = filter;
    return PrefixView(_matched, _matched.length);
  }

  @override
  Future<void> close() async {
    _gate.dispose();
    await _events.cancel();
    return super.close();
  }
}
