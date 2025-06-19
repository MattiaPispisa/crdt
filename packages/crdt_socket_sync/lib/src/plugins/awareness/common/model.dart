/// Client awareness state
class ClientAwareness {
  /// Constructor
  const ClientAwareness({
    required this.clientId,
    required this.metadata,
    required this.lastUpdate,
  });

  /// from json
  factory ClientAwareness.fromJson(Map<String, dynamic> json) =>
      ClientAwareness(
        clientId: json['clientId'] as String,
        metadata: json['metadata'] as Map<String, dynamic>,
        lastUpdate: json['lastUpdate'] as int,
      );

  /// client id
  // TODO(mattia): peerId!
  final String clientId;

  /// client metadata
  final Map<String, dynamic> metadata;

  /// last update timestamp
  final int lastUpdate;

  /// to json
  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'metadata': metadata,
        'lastUpdate': lastUpdate,
      };

  /// copy with
  ClientAwareness copyWith({
    String? clientId,
    Map<String, dynamic>? metadata,
    int? lastUpdate,
  }) {
    return ClientAwareness(
      clientId: clientId ?? this.clientId,
      metadata: metadata ?? Map<String, dynamic>.from(this.metadata),
      lastUpdate: lastUpdate ?? this.lastUpdate,
    );
  }

  @override
  String toString() => 'AwarenessState(clientId: $clientId, '
      'metadata: $metadata, lastUpdate: $lastUpdate)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClientAwareness &&
          runtimeType == other.runtimeType &&
          clientId == other.clientId &&
          metadata == other.metadata &&
          lastUpdate == other.lastUpdate;

  @override
  int get hashCode => Object.hash(clientId, metadata, lastUpdate);
}

/// Document awareness state
class DocumentAwareness {
  /// Constructor
  const DocumentAwareness({
    required this.documentId,
    required this.states,
  });

  /// from json
  factory DocumentAwareness.fromJson(Map<String, dynamic> json) =>
      DocumentAwareness(
        documentId: json['documentId'] as String,
        states: (json['states'] as Map<String, dynamic>).map(
          (k, v) =>
              MapEntry(k, ClientAwareness.fromJson(v as Map<String, dynamic>)),
        ),
      );

  /// document id
  final String documentId;

  /// map of client awareness states
  final Map<String, ClientAwareness> states;

  /// to json
  Map<String, dynamic> toJson() => {
        'documentId': documentId,
        'states': states.map((k, v) => MapEntry(k, v.toJson())),
      };

  /// copy with
  DocumentAwareness copyWith({
    String? documentId,
    Map<String, ClientAwareness>? states,
  }) {
    return DocumentAwareness(
      documentId: documentId ?? this.documentId,
      states: states ?? Map<String, ClientAwareness>.from(this.states),
    );
  }

  /// Creates a new DocumentAwareness with the updated client awareness.
  DocumentAwareness copyWithUpdatedClient(ClientAwareness client) {
    final newStates = Map<String, ClientAwareness>.from(states);
    newStates[client.clientId] = client;
    return copyWith(states: newStates);
  }

  /// Creates a new DocumentAwareness with the removed client awareness.
  DocumentAwareness copyWithRemovedClient(String clientId) {
    final newStates = Map<String, ClientAwareness>.from(states)
      ..remove(clientId);
    return copyWith(states: newStates);
  }

  @override
  String toString() => 'DocumentAwareness(documentId: $documentId, '
      'states: $states)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentAwareness &&
          runtimeType == other.runtimeType &&
          documentId == other.documentId &&
          _mapEquals(states, other.states);

  @override
  int get hashCode => Object.hash(documentId, states);
}

bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) {
      return false;
    }
  }

  return true;
}
