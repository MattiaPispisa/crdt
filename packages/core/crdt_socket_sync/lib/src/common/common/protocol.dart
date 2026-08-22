/// Class that handles the communication protocol.
class Protocol {
  /// Version
  static const String version = '1.0.0';

  /// Handshake timeout
  static const Duration handshakeTimeout = Duration(milliseconds: 5000);

  /// Ping timeout
  static const Duration pingTimeout = Duration(milliseconds: 30000);

  /// Ping interval
  static const Duration pingInterval = Duration(milliseconds: 15000);

  /// Client timeout (time after which a client is considered disconnected)
  static final Duration clientTimeout =
      Duration(seconds: pingInterval.inSeconds * 4);

  /// Maximum reconnect attempts
  static const int maxReconnectAttempts = 5;

  /// Reconnect interval
  static const Duration reconnectInterval = Duration(milliseconds: 1000);

  /// Maximum buffer size
  static const int maxBufferSize = 1024 * 1024; // 1MB

  /// Error handshake failed
  static const String errorHandshakeFailed = 'HANDSHAKE_FAILED';

  /// Error connection closed
  static const String errorConnectionClosed = 'CONNECTION_CLOSED';

  /// Error invalid message
  static const String errorInvalidMessage = 'INVALID_MESSAGE';

  /// Error timeout
  static const String errorTimeout = 'TIMEOUT';

  /// Error internal error
  static const String errorInternalError = 'INTERNAL_ERROR';

  /// Error document not found
  static const String errorDocumentNotFound = 'DOCUMENT_NOT_FOUND';

  /// Error client out of sync
  static const String errorOutOfSync = 'OUT_OF_SYNC';
}
