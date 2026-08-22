part of 'document_changes_cubit.dart';

/// JSON descriptor of a CRDT change as returned by
/// `describeChangesJson(trackedId)` on the target side.
///
/// Holding a [Change] decoded from [bytes] is optional — callers that just
/// need to render metadata can stick to the lighter fields.
class ChangeDescriptor extends Equatable {
  const ChangeDescriptor({
    required this.id,
    required this.hlc,
    required this.author,
    required this.deps,
    required this.payloadSize,
    required this.bytes,
  });

  factory ChangeDescriptor.fromJson(Map<String, dynamic> json) {
    return ChangeDescriptor(
      id: json['id'] as String,
      hlc: json['hlc'] as String,
      author: json['author'] as String,
      deps: (json['deps'] as List<dynamic>).cast<String>(),
      payloadSize: json['payloadSize'] as int,
      bytes: base64Decode(json['bytes'] as String),
    );
  }

  final String id;
  final String hlc;
  final String author;
  final List<String> deps;
  final int payloadSize;
  final Uint8List bytes;

  /// Lazily decode the full [crdt_lf.Change] from [bytes].
  ///
  /// Useful when the UI needs more than the descriptor fields (e.g., to
  /// re-encode or replay the change). For listing changes the descriptor
  /// alone is sufficient.
  crdt_lf.Change decodeChange() => crdt_lf.Change.fromBytes(bytes);

  @override
  List<Object?> get props => [id, hlc, author, deps, payloadSize];
}

class DocumentChangesState extends Equatable {
  const DocumentChangesState({
    required this.loading,
    required this.error,
    required this.changes,
  });

  factory DocumentChangesState.initial() =>
      const DocumentChangesState(loading: false, error: null, changes: []);

  final bool loading;
  final String? error;
  final List<ChangeDescriptor> changes;

  DocumentChangesState copyWith({
    bool? loading,
    String? error,
    List<ChangeDescriptor>? changes,
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
