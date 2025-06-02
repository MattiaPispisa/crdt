/// Enum representing the server event types
enum ServerEventType {
  /// The server has been started
  started,

  /// The server has been stopped
  stopped,

  /// A client has connected.
  clientConnected,

  /// A client has completed the handshake.
  clientHandshake,

  /// A client has requested a snapshot.
  /// The sever accepts the request and creates a snapshot.
  clientSnapshotCreated,

  /// A client has sent a change.
  /// The server applies the change to the document.
  clientChangeApplied,

  /// A client has requested a ping
  clientPingRequest,

  /// A client has disconnected
  clientDisconnected,

  /// An error has occurred
  error,
}

/// Class representing a server event
class ServerEvent {
  /// Constructor
  const ServerEvent({
    required this.type,
    required this.message,
    this.data,
  });

  /// The event type
  final ServerEventType type;

  /// The associated message
  final String message;

  /// Additional data associated with the event (optional)
  final Map<String, dynamic>? data;

  @override
  String toString() {
    return 'ServerEvent(type: $type, message: $message, data: $data)';
  }
}
