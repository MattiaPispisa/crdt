/// Marker interface for the type of a [SessionEvent].
///
/// Session event type enums implement it, so [SessionEvent.type] can hold any
/// of them through a common supertype.
abstract class SessionEventTypeValue {}

/// Session event types shared by every communication mode.
enum SessionEventType implements SessionEventTypeValue {
  /// Ping received
  pingReceived,

  /// Client disconnected
  disconnected,

  /// Error occurred
  error,
}

/// Session event.
abstract class SessionEvent {
  /// Constructor
  const SessionEvent({
    required this.type,
    required this.message,
    required this.sessionId,
  });

  /// The event type
  final SessionEventTypeValue type;

  /// The message associated with the event
  final String message;

  /// The session id
  final String sessionId;
}

/// Session event for a generic shared event (error, ping, disconnect).
class SessionEventGeneric extends SessionEvent {
  /// Constructor
  const SessionEventGeneric({
    required super.sessionId,
    required super.message,
    required SessionEventType super.type,
    this.data,
  });

  @override
  SessionEventType get type => super.type as SessionEventType;

  /// The data associated with the event
  final Map<String, dynamic>? data;
}
