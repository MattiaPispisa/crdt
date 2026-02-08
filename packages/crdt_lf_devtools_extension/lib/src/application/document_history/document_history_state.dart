part of 'document_history_cubit.dart';

class DocumentHistoryState extends Equatable {
  const DocumentHistoryState({
    required this.loading,
    required this.error,
    required this.length,
    required this.changes,
    required this.cursor,
  });

  factory DocumentHistoryState.initial() => const DocumentHistoryState(
        loading: false,
        error: null,
        length: null,
        changes: null,
        cursor: null,
      );

  final bool loading;
  final String? error;

  /// Total number of changes in the timeline.
  final int? length;

  /// Ordered list of changes (by HLC).
  final List<ChangeDescriptor>? changes;

  /// Current cursor position. `0` = empty/initial state; `length` = full state.
  final int? cursor;

  DocumentHistoryState copyWith({
    bool? loading,
    String? error,
    int? length,
    List<ChangeDescriptor>? changes,
    int? cursor,
  }) {
    return DocumentHistoryState(
      loading: loading ?? this.loading,
      error: error ?? this.error,
      length: length ?? this.length,
      changes: changes ?? this.changes,
      cursor: cursor ?? this.cursor,
    );
  }

  @override
  List<Object?> get props => [loading, error, length, changes, cursor];
}
