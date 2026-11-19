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

  /// Whether [entry] passes every filter.
  bool matches(MirrorEntry entry) {
    final change = entry.change;
    if (author != null && change.author.toString() != author) return false;
    if (handler != null && entry.handlerId != handler) return false;
    if (kind != null && entry.kind != kind) return false;
    final needle = text.trim().toLowerCase();
    return needle.isEmpty ||
        change.id.toString().toLowerCase().contains(needle);
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
  factory ChangeIndex(List<MirrorEntry> entries) {
    final byId = <OperationId, MirrorEntry>{};
    final dependents = <OperationId, List<OperationId>>{};
    final authors = <String>{};
    final handlers = <String>{};
    final kinds = <int>{};
    for (final entry in entries) {
      final change = entry.change;
      byId[change.id] = entry;
      for (final dep in entry.deps) {
        (dependents[dep] ??= []).add(change.id);
      }
      authors.add(change.author.toString());
      if (entry.handlerId case final id?) handlers.add(id);
      if (entry.kind case final kind?) kinds.add(kind);
    }
    final graph = LaneGraph([
      for (final entry in entries)
        (
          author: entry.change.author.toString(),
          depAuthors: [for (final d in entry.deps) d.peerId.toString()],
        ),
    ]);
    return ChangeIndex._(
      entries,
      graph,
      byId,
      dependents,
      authors.toList()..sort(),
      handlers.toList()..sort(),
      kinds.toList()..sort(),
    );
  }

  const ChangeIndex._(
    this.entries,
    this.graph,
    this.byId,
    this._dependents,
    this.authors,
    this.handlers,
    this.kinds,
  );

  /// The index of no change.
  static const ChangeIndex empty = ChangeIndex._(
    [],
    LaneGraph.empty,
    {},
    {},
    [],
    [],
    [],
  );

  /// The changes, in replay order.
  final List<MirrorEntry> entries;

  /// The lane graph of [entries], one row each.
  final LaneGraph graph;

  final Map<OperationId, MirrorEntry> byId;

  final Map<OperationId, List<OperationId>> _dependents;

  /// The distinct authors, sorted.
  final List<String> authors;

  /// The distinct handler ids, sorted.
  final List<String> handlers;

  /// The distinct operation kinds, sorted.
  final List<int> kinds;

  /// The loaded changes that list [id] as a dependency.
  List<OperationId> dependentsOf(OperationId id) => _dependents[id] ?? const [];
}

/// The change list of a document, its filters and the selected change.
///
/// It holds no value equality: comparing every change on each emit would
/// cost more than a rebuild.
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
  MirrorEntry? get selected => index.byId[selectedId];

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
