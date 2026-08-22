/// server awareness event type
enum ServerAwarenessEventType {
  /// a client joined
  clientJoined,

  /// a client updated its state
  clientUpdated,

  /// a client left
  clientLeft,
}

/// server awareness event
class ServerAwarenessEvent {
  /// constructor
  ServerAwarenessEvent({
    required this.type,
    required this.documentId,
    required this.clientId,
  });

  /// event type
  final ServerAwarenessEventType type;

  /// document id
  final String documentId;

  /// client id
  final String clientId;

  @override
  String toString() => 'ServerAwarenessEvent(type: $type, '
      'documentId: $documentId, clientId: $clientId)';
}
