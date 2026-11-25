// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'documents_cubit.dart';

/// The outcome of the last load of the documents.
enum DocumentsStatus {
  /// No load ended yet.
  initial,

  /// The last load succeeded.
  loaded,

  /// The last load failed; the documents are the ones loaded before.
  failure,
}

/// The live documents of the app and the selected one.
class DocumentsState extends Equatable {
  const DocumentsState({
    this.status = DocumentsStatus.initial,
    this.documents = const [],
    this.selectedId,
    this.error,
  });

  final DocumentsStatus status;

  final List<DocumentSummary> documents;

  /// The tracked id of the selected document; `null` when there is none.
  final int? selectedId;

  /// The error of the last load; `null` unless [status] is a failure.
  final String? error;

  /// The selected document; `null` when there is none.
  DocumentSummary? get selected {
    for (final document in documents) {
      if (document.id == selectedId) return document;
    }
    return null;
  }

  @override
  List<Object?> get props => [status, documents, selectedId, error];
}
