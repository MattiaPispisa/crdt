part of 'documents_cubit.dart';

class DocumentsState extends Equatable {
  const DocumentsState({
    required this.loading,
    required this.error,
    required this.documents,
    required this.selectedDocument,
  });

  factory DocumentsState.initial() {
    return const DocumentsState(
      loading: true,
      error: null,
      documents: [],
      selectedDocument: null,
    );
  }

  final bool loading;
  final String? error;
  final List<TrackedDocument> documents;

  final TrackedDocument? selectedDocument;

  DocumentsState copyWith({
    bool? loading,
    String? error,
    List<TrackedDocument>? documents,
    TrackedDocument? selectedDocument,
  }) {
    return DocumentsState(
      loading: loading ?? this.loading,
      error: error ?? this.error,
      documents: documents ?? this.documents,
      selectedDocument: selectedDocument ?? this.selectedDocument,
    );
  }

  @override
  List<Object?> get props => [
        loading,
        error,
        documents,
        selectedDocument,
      ];
}

class TrackedDocument extends Equatable {
  const TrackedDocument({
    required this.id,
    required this.document,
  });

  final int id;
  final Instance document;

  @override
  List<Object?> get props => [id, document];
}
