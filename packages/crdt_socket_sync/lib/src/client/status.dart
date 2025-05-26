/// Enum that represents the status of the connection
enum ConnectionStatus {
  /// The client is connected to the server
  connected,

  /// The client is disconnected from the server
  disconnected,

  /// The client is reconnecting to the server
  reconnecting,

  /// An error occurred in the connection
  error,
}
