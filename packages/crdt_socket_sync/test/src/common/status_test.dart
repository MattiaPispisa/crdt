import 'package:crdt_socket_sync/client.dart';
import 'package:test/test.dart';

void main() {
  group('ConnectionStatus', () {
    test('should getter methods work correctly', () {
      expect(ConnectionStatus.connected.isConnected, isTrue);
      expect(ConnectionStatus.connected.isDisconnected, isFalse);
      expect(ConnectionStatus.connected.isConnecting, isFalse);
      expect(ConnectionStatus.connected.isReconnecting, isFalse);
      expect(ConnectionStatus.connected.isError, isFalse);

      expect(ConnectionStatus.disconnected.isConnected, isFalse);
      expect(ConnectionStatus.disconnected.isDisconnected, isTrue);
      expect(ConnectionStatus.disconnected.isConnecting, isFalse);
      expect(ConnectionStatus.disconnected.isReconnecting, isFalse);
      expect(ConnectionStatus.disconnected.isError, isFalse);

      expect(ConnectionStatus.connecting.isConnected, isFalse);
      expect(ConnectionStatus.connecting.isDisconnected, isFalse);
      expect(ConnectionStatus.connecting.isConnecting, isTrue);
      expect(ConnectionStatus.connecting.isReconnecting, isFalse);
      expect(ConnectionStatus.connecting.isError, isFalse);

      expect(ConnectionStatus.reconnecting.isConnected, isFalse);
      expect(ConnectionStatus.reconnecting.isDisconnected, isFalse);
      expect(ConnectionStatus.reconnecting.isConnecting, isFalse);
      expect(ConnectionStatus.reconnecting.isReconnecting, isTrue);
      expect(ConnectionStatus.reconnecting.isError, isFalse);

      expect(ConnectionStatus.error.isConnected, isFalse);
      expect(ConnectionStatus.error.isDisconnected, isFalse);
      expect(ConnectionStatus.error.isConnecting, isFalse);
      expect(ConnectionStatus.error.isReconnecting, isFalse);
      expect(ConnectionStatus.error.isError, isTrue);
    });
  });
}
