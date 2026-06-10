part of 'document_detail_cubit.dart';

/// JSON descriptor of a registered handler.
class HandlerSummary extends Equatable {
  const HandlerSummary({
    required this.id,
    required this.type,
    required this.value,
  });

  factory HandlerSummary.fromJson(Map<String, dynamic> json) => HandlerSummary(
    id: json['id'] as String,
    type: json['type'] as String,
    value: json['value'] as String,
  );

  /// Handler instance id (the same one passed to its constructor).
  final String id;

  /// Runtime type of the handler (e.g. `CRDTTextHandler`).
  final String type;

  /// Stringified current value (whatever `Handler.toString()` returns).
  final String value;

  @override
  List<Object?> get props => [id, type, value];
}

class DocumentDetailState extends Equatable {
  const DocumentDetailState({
    required this.loading,
    required this.error,
    required this.document,
    required this.handlers,
  });

  factory DocumentDetailState.initial() => const DocumentDetailState(
    loading: false,
    error: null,
    document: null,
    handlers: null,
  );

  final bool loading;
  final String? error;
  final TrackedDocument? document;
  final List<HandlerSummary>? handlers;

  DocumentDetailState copyWith({
    bool? loading,
    String? error,
    TrackedDocument? document,
    List<HandlerSummary>? handlers,
  }) {
    return DocumentDetailState(
      loading: loading ?? this.loading,
      error: error ?? this.error,
      document: document ?? this.document,
      handlers: handlers ?? this.handlers,
    );
  }

  @override
  List<Object?> get props => [loading, error, document, handlers];
}
