/// Enum that represents the status of the connection
enum ConnectionStatus {
  /// The client is connected to the server
  connected,

  /// The client is disconnected from the server
  disconnected,

  /// The client is connecting to the server
  connecting,

  /// The client is reconnecting to the server
  reconnecting,

  /// An error occurred in the connection
  error;

  /// Whether the client is connected to the server
  bool get isConnected => this == connected;

  /// Whether the client is disconnected from the server
  bool get isDisconnected => this == disconnected;

  /// Whether the client is connecting to the server
  bool get isConnecting => this == connecting;

  /// Whether the client is reconnecting to the server
  bool get isReconnecting => this == reconnecting;

  /// Whether the client is in an error state
  bool get isError => this == error;
}
