// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'change_log_cubit.dart';

/// The filters of the change list; a `null` field matches every change.
class ChangeFilter extends Equatable {
  const ChangeFilter({this.author, this.handler, this.kind, this.text = ''});

  final String? author;

  final String? handler;

  final int? kind;

  /// Matched against the change id, ignoring case and outer spaces.
  final String text;

  /// Whether every change matches.
  bool get isEmpty =>
      author == null && handler == null && kind == null && text.trim().isEmpty;

  /// A test that tells whether an entry passes every filter; build it once
  /// for many entries.
  bool Function(MirrorEntry entry) matcher() {
    final author = this.author == null ? null : PeerId.parse(this.author!);
    final needle = text.trim().toLowerCase();
    return (entry) =>
        (author == null || entry.change.author == author) &&
        (handler == null || entry.handlerId == handler) &&
        (kind == null || entry.kind == kind) &&
        (needle.isEmpty || entry.idText.contains(needle));
  }

  ChangeFilter copyWith({
    String? Function()? author,
    String? Function()? handler,
    int? Function()? kind,
    String? text,
  }) => ChangeFilter(
    author: author == null ? this.author : author(),
    handler: handler == null ? this.handler : handler(),
    kind: kind == null ? this.kind : kind(),
    text: text ?? this.text,
  );

  @override
  List<Object?> get props => [author, handler, kind, text];
}

/// The changes of one sync, with the lookups the tab needs.
class ChangeIndex {
  /// Indexes [entries], given in replay order.
  factory ChangeIndex(List<MirrorEntry> entries) => empty.extend(entries);

  const ChangeIndex._(
    this._tables,
    this._length,
    this.graph,
    this.authors,
    this.handlers,
    this.kinds,
  );

  /// The index of no change.
  static const ChangeIndex empty = ChangeIndex._(
    null,
    0,
    LaneGraph.empty,
    [],
    [],
    [],
  );

  // Shared with the indexes built from this one.
  final _IndexTables? _tables;

  final int _length;

  /// The lane graph of [entries], one row each.
  final LaneGraph graph;

  /// The distinct authors, sorted.
  final List<String> authors;

  /// The distinct handler ids, sorted.
  final List<String> handlers;

  /// The distinct operation kinds, sorted.
  final List<int> kinds;

  /// The changes, in replay order.
  List<MirrorEntry> get entries => switch (_tables) {
    null => const [],
    final tables => PrefixView(tables.entries, _length),
  };

  /// This index with [added] after its entries, in replay order; this index
  /// stays as it is.
  ChangeIndex extend(List<MirrorEntry> added) => replaceFrom(_length, added);

  /// This index with its entries from [from] on replaced by [added], in
  /// replay order.
  ///
  /// Below its length, it can change the entries of this index and of the
  /// indexes this one was built from: call it on the last index only.
  ChangeIndex replaceFrom(int from, List<MirrorEntry> added) {
    final tables = _tables;
    if (tables != null && tables.entries.length != _length) {
      return empty.extend([...tables.entries.take(from), ...added]);
    }
    final next =
        (tables ?? _IndexTables())
          ..truncate(from)
          ..addAll(added);
    return ChangeIndex._(
      next,
      next.entries.length,
      graph.replaceFrom(from, [
        for (final entry in added)
          (
            author: entry.change.author.toString(),
            depAuthors: [for (final d in entry.deps) d.peerId.toString()],
          ),
      ]),
      next.authors.sortedOr(authors),
      next.handlers.sortedOr(handlers),
      next.kinds.sortedOr(kinds),
    );
  }

  /// The change [id]; `null` when this index does not hold it.
  MirrorEntry? entryOf(OperationId id) {
    final at = _tables?.positions[id];
    return at == null || at >= _length ? null : _tables!.entries[at];
  }

  /// The changes of this index that list [id] as a dependency.
  List<OperationId> dependentsOf(OperationId id) {
    final tables = _tables;
    final dependents = tables?.dependents[id];
    if (tables == null || dependents == null) return const [];
    return [
      for (final dependent in dependents)
        if (tables.positions[dependent]! < _length) dependent,
    ];
  }
}

class _IndexTables {
  _IndexTables()
    : entries = <MirrorEntry>[],
      positions = <OperationId, int>{},
      dependents = <OperationId, List<OperationId>>{},
      authors = _Counts<String>(),
      handlers = _Counts<String>(),
      kinds = _Counts<int>();

  final List<MirrorEntry> entries;

  final Map<OperationId, int> positions;

  final Map<OperationId, List<OperationId>> dependents;

  final _Counts<String> authors;

  final _Counts<String> handlers;

  final _Counts<int> kinds;

  void addAll(List<MirrorEntry> added) {
    for (final entry in added) {
      final change = entry.change;
      positions[change.id] = entries.length;
      entries.add(entry);
      for (final dep in entry.deps) {
        (dependents[dep] ??= []).add(change.id);
      }
      authors.add(change.author.toString());
      if (entry.handlerId case final id?) handlers.add(id);
      if (entry.kind case final kind?) kinds.add(kind);
    }
  }

  /// Drops the entries from [from] on.
  void truncate(int from) {
    for (var i = entries.length - 1; i >= from; i--) {
      final entry = entries[i];
      final change = entry.change;
      positions.remove(change.id);
      // Last in, first out: a dropped entry is the last dependent of each
      // of its dependencies.
      for (final dep in entry.deps) {
        final list = dependents[dep]!..removeLast();
        if (list.isEmpty) dependents.remove(dep);
      }
      authors.remove(change.author.toString());
      if (entry.handlerId case final id?) handlers.remove(id);
      if (entry.kind case final kind?) kinds.remove(kind);
    }
    if (from < entries.length) entries.length = from;
  }
}

// How many entries hold each value.
class _Counts<T extends Comparable<Object>> {
  _Counts() : _counts = <T, int>{};

  final Map<T, int> _counts;

  bool _moved = false;

  void add(T value) {
    final count = _counts[value] ?? 0;
    _counts[value] = count + 1;
    if (count == 0) _moved = true;
  }

  void remove(T value) {
    final count = _counts[value]! - 1;
    if (count == 0) {
      _counts.remove(value);
      _moved = true;
    } else {
      _counts[value] = count;
    }
  }

  /// The values, sorted; [previous] when no value came or left since the
  /// last call.
  List<T> sortedOr(List<T> previous) {
    if (!_moved) return previous;
    _moved = false;
    return List.unmodifiable(_counts.keys.toList()..sort());
  }
}

/// The change list of a document, its filters and the selected change.
// No value equality: comparing every change on each emit costs more than a
// rebuild.
class ChangeLogState {
  const ChangeLogState({
    this.status = LoadStatus.initial,
    this.progress,
    this.index = ChangeIndex.empty,
    this.visible = const [],
    this.filter = const ChangeFilter(),
    this.newestFirst = true,
    this.selectedId,
    this.operationStatus = LoadStatus.initial,
    this.operation,
    this.operationError,
    this.error,
  });

  final LoadStatus status;

  /// The progress of the first sync; `null` before its first page.
  final LoadProgress? progress;

  final ChangeIndex index;

  /// The changes that pass [filter], in the order of [newestFirst].
  final List<MirrorEntry> visible;

  final ChangeFilter filter;

  final bool newestFirst;

  /// The selected change, shown even when [filter] hides it; `null` when
  /// there is none.
  final OperationId? selectedId;

  /// The outcome of the last operation load of the selected change.
  final LoadStatus operationStatus;

  /// The operation of the selected change; `null` until it loads.
  final OperationInfo? operation;

  /// The error of the last operation load; `null` unless it failed.
  final String? operationError;

  /// The error of the last sync; `null` unless [status] is a failure.
  final String? error;

  /// The selected change; `null` when there is none or a prune dropped it.
  MirrorEntry? get selected =>
      selectedId == null ? null : index.entryOf(selectedId!);

  ChangeLogState _copyWith({
    LoadStatus? status,
    LoadProgress? Function()? progress,
    ChangeIndex? index,
    List<MirrorEntry>? visible,
    ChangeFilter? filter,
    bool? newestFirst,
    OperationId? Function()? selectedId,
    LoadStatus? operationStatus,
    OperationInfo? Function()? operation,
    String? Function()? operationError,
    String? Function()? error,
  }) => ChangeLogState(
    status: status ?? this.status,
    progress: progress == null ? this.progress : progress(),
    index: index ?? this.index,
    visible: visible ?? this.visible,
    filter: filter ?? this.filter,
    newestFirst: newestFirst ?? this.newestFirst,
    selectedId: selectedId == null ? this.selectedId : selectedId(),
    operationStatus: operationStatus ?? this.operationStatus,
    operation: operation == null ? this.operation : operation(),
    operationError:
        operationError == null ? this.operationError : operationError(),
    error: error == null ? this.error : error(),
  );
}
