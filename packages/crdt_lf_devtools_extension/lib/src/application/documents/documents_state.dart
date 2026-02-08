part of 'documents_cubit.dart';

/// Read-only summary of a CRDT document tracked by devtools.
class TrackedDocument extends Equatable {
  const TrackedDocument({
    required this.id,
    required this.documentId,
    required this.peerId,
    required this.changesCount,
    required this.handlersCount,
    required this.version,
  });

  /// Build a [TrackedDocument] from the JSON object returned by
  /// `describeDocumentsJson()` / `describeDocumentJson()`.
  factory TrackedDocument.fromJson(Map<String, dynamic> json) {
    return TrackedDocument(
      id: json['id'] as int,
      documentId: json['documentId'] as String,
      peerId: json['peerId'] as String,
      changesCount: json['changesCount'] as int,
      handlersCount: json['handlersCount'] as int,
      version: (json['version'] as List<dynamic>).cast<String>(),
    );
  }

  /// Devtools-local numeric id.
  final int id;

  /// The CRDT document id.
  final String documentId;

  /// The peer that owns this document.
  final String peerId;

  /// Number of changes currently in the document.
  final int changesCount;

  /// Number of handlers currently registered on the document.
  final int handlersCount;

  /// Current frontier (set of operation ids).
  final List<String> version;

  /// Short human label used in the document selector.
  String get displayLabel =>
      '#$id · ${documentId.substring(0, documentId.length.clamp(0, 8))}'
      '… · peer ${peerId.substring(0, peerId.length.clamp(0, 8))}…';

  @override
  List<Object?> get props => [
        id,
        documentId,
        peerId,
        changesCount,
        handlersCount,
        version,
      ];
}

class DocumentsState extends Equatable {
  const DocumentsState({
    required this.loading,
    required this.error,
    required this.documents,
    required this.selectedDocument,
  });

  factory DocumentsState.initial() {
    return const DocumentsState(
      loading: false,
      error: null,
      documents: null,
      selectedDocument: null,
    );
  }

  final bool loading;
  final String? error;
  final List<TrackedDocument>? documents;
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
  List<Object?> get props => [loading, error, documents, selectedDocument];
}
