part of 'document_changes_cubit.dart';

class DocumentChangesState extends Equatable {
  const DocumentChangesState({
    required this.loading,
    required this.error,
    required this.changes,
  });

  factory DocumentChangesState.initial() {
    return const DocumentChangesState(
      loading: false,
      error: null,
      changes: [],
    );
  }

  final bool loading;
  final String? error;
  final List<crdt_lf.Change> changes;

  DocumentChangesState copyWith({
    bool? loading,
    String? error,
    List<crdt_lf.Change>? changes,
  }) {
    return DocumentChangesState(
      loading: loading ?? this.loading,
      error: error ?? this.error,
      changes: changes ?? this.changes,
    );
  }

  @override
  List<Object?> get props => [loading, error, changes];
}

