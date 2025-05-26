import 'package:crdt_lf/crdt_lf.dart';

/// Available session events
enum SessionEventType {
  /// Handshake completed
  handshakeCompleted,

  /// Change received
  changeReceived,

  /// Client disconnected
  disconnected,

  /// Error occurred
  error,
}

/// Session event
abstract class SessionEvent {
  /// Constructor
  const SessionEvent({
    required this.type,
    required this.message,
    required this.sessionId,
  });

  /// The event type
  final SessionEventType type;

  /// The message associated with the event
  final String message;

  /// The session id
  final String sessionId;
}

/// Session event for a change received
class SessionEventChangeReceived extends SessionEvent {
  /// Constructor
  const SessionEventChangeReceived({
    required super.sessionId,
    required super.message,
    required this.change,
    required this.documentId,
  }) : super(type: SessionEventType.changeReceived);

  /// The change that was received
  final Change change;

  /// The document id
  final String documentId;
}

/// Session event for a generic event
class SessionEventGeneric extends SessionEvent {
  /// Constructor
  const SessionEventGeneric({
    required super.sessionId,
    required super.message,
    required super.type,
    this.data,
  });

  /// The data associated with the event
  final Map<String, dynamic>? data;
}
