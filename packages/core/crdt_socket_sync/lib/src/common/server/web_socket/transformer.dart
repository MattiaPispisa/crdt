import 'dart:io';

/// WebSocket server transformer
abstract class WebSocketServerTransformer {
  /// Check if the request is an upgrade request
  bool isUpgradeRequest(HttpRequest request);

  /// Upgrade the request to a WebSocket connection
  Future<WebSocket> upgrade(HttpRequest request);
}

/// Default [WebSocketServerTransformer], backed by **`dart:io`**'s
/// [WebSocketTransformer].
class DefaultWebSocketServerTransformer implements WebSocketServerTransformer {
  @override
  bool isUpgradeRequest(HttpRequest request) {
    return WebSocketTransformer.isUpgradeRequest(request);
  }

  @override
  Future<WebSocket> upgrade(HttpRequest request) {
    return WebSocketTransformer.upgrade(request);
  }
}
