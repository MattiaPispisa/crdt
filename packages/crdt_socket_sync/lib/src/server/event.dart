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
  clientDocumentStatusCreated,

  /// A client has sent a change.
  /// The server applies the change to the document.
  clientChangeApplied,

  /// A client has requested a ping
  clientPingRequest,

  /// A client has disconnected
  clientDisconnected,

  /// An error has occurred
  error,

  /// A client is out of sync
  clientOutOfSync,

  /// A message has been broadcasted to clients
  messageBroadcasted,

  /// A message has been sent to a client
  messageSent;

  /// Whether the event is started
  bool get isStarted => this == started;

  /// Whether the event is stopped
  bool get isStopped => this == stopped;

  /// Whether the event is client connected
  bool get isClientConnected => this == clientConnected;

  /// Whether the event is client handshake
  bool get isClientHandshake => this == clientHandshake;

  /// Whether the event is client document status created
  bool get isClientDocumentStatusCreated => this == clientDocumentStatusCreated;

  /// Whether the event is client change applied
  bool get isClientChangeApplied => this == clientChangeApplied;

  /// Whether the event is client ping request
  bool get isClientPingRequest => this == clientPingRequest;

  /// Whether the event is client disconnected
  bool get isClientDisconnected => this == clientDisconnected;

  /// Whether the event is client out of sync
  bool get isClientOutOfSync => this == clientOutOfSync;

  /// Whether the event is a client event
  bool get isError => this == error;

  /// Whether the event is a broadcast event
  bool get isMessageBroadcasted => this == messageBroadcasted;

  /// Whether the event is a sent event
  bool get isMessageSent => this == messageSent;
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
