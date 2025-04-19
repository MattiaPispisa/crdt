part of 'document_changes_cubit.dart';

class DocumentChangesState extends Equatable {
  const DocumentChangesState({
    required this.loading,
    required this.error,
    required this.descriptors,
  });

  factory DocumentChangesState.initial() {
    return const DocumentChangesState(
      loading: true,
      error: null,
      descriptors: [],
    );
  }

  final bool loading;
  final String? error;
  final List<DocumentChangeDescriptor> descriptors;

  DocumentChangesState copyWith({
    bool? loading,
    String? error,
    List<DocumentChangeDescriptor>? descriptors,
  }) {
    return DocumentChangesState(
      loading: loading ?? this.loading,
      error: error ?? this.error,
      descriptors: descriptors ?? this.descriptors,
    );
  }

  @override
  List<Object?> get props => [loading, error, descriptors];
}

class DocumentChangeDescriptor extends Equatable {
  const DocumentChangeDescriptor({
    required this.description,
  });

  final String description;

  @override
  List<Object?> get props => [description];
}
