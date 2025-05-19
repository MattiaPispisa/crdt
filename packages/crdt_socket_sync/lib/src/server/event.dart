/// Enum representing the server event types
enum ServerEventType {
  /// The server has been started
  started,

  /// The server has been stopped
  stopped,

  /// A client has connected
  clientConnected,

  /// A client has completed the handshake
  clientHandshake,

  /// A client has disconnected
  clientDisconnected,

  /// A snapshot has been created
  snapshotCreated,

  /// A new document has been registered
  documentRegistered,

  /// A document has been unregistered
  documentUnregistered,

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
}
