import 'package:crdt_socket_sync/web_socket_server.dart';
import 'package:test/test.dart';

void main() {
  group('ServerEvent', () {
    test('should type getter methods work correctly', () {
      expect(ServerEventType.started.isStarted, isTrue);
      expect(ServerEventType.started.isStopped, isFalse);
      expect(ServerEventType.started.isClientConnected, isFalse);
      expect(ServerEventType.started.isClientHandshake, isFalse);
      expect(ServerEventType.started.isClientDocumentStatusCreated, isFalse);
      expect(ServerEventType.started.isClientChangeApplied, isFalse);
      expect(ServerEventType.started.isClientPingRequest, isFalse);
      expect(ServerEventType.started.isClientDisconnected, isFalse);
      expect(ServerEventType.started.isClientOutOfSync, isFalse);
      expect(ServerEventType.started.isError, isFalse);
      expect(ServerEventType.started.isMessageBroadcasted, isFalse);
      expect(ServerEventType.started.isMessageSent, isFalse);

      expect(ServerEventType.stopped.isStarted, isFalse);
      expect(ServerEventType.stopped.isStopped, isTrue);
      expect(ServerEventType.stopped.isClientConnected, isFalse);
      expect(ServerEventType.stopped.isClientHandshake, isFalse);
      expect(ServerEventType.stopped.isClientDocumentStatusCreated, isFalse);
      expect(ServerEventType.stopped.isClientChangeApplied, isFalse);
      expect(ServerEventType.stopped.isClientPingRequest, isFalse);
      expect(ServerEventType.stopped.isClientDisconnected, isFalse);
      expect(ServerEventType.stopped.isClientOutOfSync, isFalse);
      expect(ServerEventType.stopped.isError, isFalse);
      expect(ServerEventType.stopped.isMessageBroadcasted, isFalse);
      expect(ServerEventType.stopped.isMessageSent, isFalse);

      expect(ServerEventType.clientConnected.isStarted, isFalse);
      expect(ServerEventType.clientConnected.isStopped, isFalse);
      expect(ServerEventType.clientConnected.isClientConnected, isTrue);
      expect(ServerEventType.clientConnected.isClientHandshake, isFalse);
      expect(
        ServerEventType.clientConnected.isClientDocumentStatusCreated,
        isFalse,
      );
      expect(ServerEventType.clientConnected.isClientChangeApplied, isFalse);
      expect(ServerEventType.clientConnected.isClientPingRequest, isFalse);
      expect(ServerEventType.clientConnected.isClientDisconnected, isFalse);
      expect(ServerEventType.clientConnected.isClientOutOfSync, isFalse);
      expect(ServerEventType.clientConnected.isError, isFalse);
      expect(ServerEventType.clientConnected.isMessageBroadcasted, isFalse);
      expect(ServerEventType.clientConnected.isMessageSent, isFalse);

      expect(ServerEventType.clientHandshake.isStarted, isFalse);
      expect(ServerEventType.clientHandshake.isStopped, isFalse);
      expect(ServerEventType.clientHandshake.isClientConnected, isFalse);
      expect(ServerEventType.clientHandshake.isClientHandshake, isTrue);
      expect(
        ServerEventType.clientHandshake.isClientDocumentStatusCreated,
        isFalse,
      );
      expect(ServerEventType.clientHandshake.isClientChangeApplied, isFalse);
      expect(ServerEventType.clientHandshake.isClientPingRequest, isFalse);
      expect(ServerEventType.clientHandshake.isClientDisconnected, isFalse);
      expect(ServerEventType.clientHandshake.isClientOutOfSync, isFalse);
      expect(ServerEventType.clientHandshake.isError, isFalse);
      expect(ServerEventType.clientHandshake.isMessageBroadcasted, isFalse);
      expect(ServerEventType.clientHandshake.isMessageSent, isFalse);

      expect(ServerEventType.clientDocumentStatusCreated.isStarted, isFalse);
      expect(ServerEventType.clientDocumentStatusCreated.isStopped, isFalse);
      expect(
        ServerEventType.clientDocumentStatusCreated.isClientConnected,
        isFalse,
      );
      expect(
        ServerEventType.clientDocumentStatusCreated.isClientHandshake,
        isFalse,
      );
      expect(
        ServerEventType
            .clientDocumentStatusCreated.isClientDocumentStatusCreated,
        isTrue,
      );
      expect(
        ServerEventType.clientDocumentStatusCreated.isClientChangeApplied,
        isFalse,
      );
      expect(
        ServerEventType.clientDocumentStatusCreated.isClientPingRequest,
        isFalse,
      );
      expect(
        ServerEventType.clientDocumentStatusCreated.isClientDisconnected,
        isFalse,
      );
      expect(
        ServerEventType.clientDocumentStatusCreated.isClientOutOfSync,
        isFalse,
      );
      expect(ServerEventType.clientDocumentStatusCreated.isError, isFalse);
      expect(
        ServerEventType.clientDocumentStatusCreated.isMessageBroadcasted,
        isFalse,
      );
      expect(
        ServerEventType.clientDocumentStatusCreated.isMessageSent,
        isFalse,
      );

      expect(ServerEventType.clientChangeApplied.isStarted, isFalse);
      expect(ServerEventType.clientChangeApplied.isStopped, isFalse);
      expect(ServerEventType.clientChangeApplied.isClientConnected, isFalse);
      expect(ServerEventType.clientChangeApplied.isClientHandshake, isFalse);
      expect(
        ServerEventType.clientChangeApplied.isClientDocumentStatusCreated,
        isFalse,
      );
      expect(ServerEventType.clientChangeApplied.isClientChangeApplied, isTrue);
      expect(ServerEventType.clientChangeApplied.isClientPingRequest, isFalse);
      expect(ServerEventType.clientChangeApplied.isClientDisconnected, isFalse);
      expect(ServerEventType.clientChangeApplied.isClientOutOfSync, isFalse);
      expect(ServerEventType.clientChangeApplied.isError, isFalse);
      expect(ServerEventType.clientChangeApplied.isMessageBroadcasted, isFalse);
      expect(ServerEventType.clientChangeApplied.isMessageSent, isFalse);
    });

    test('should constructor work correctly', () {
      const event = ServerEvent(
        type: ServerEventType.started,
        message: 'test',
      );

      expect(event.type, ServerEventType.started);
      expect(event.message, 'test');
      expect(event.data, isNull);
      expect(
        event.toString(),
        'ServerEvent(type: ServerEventType.started, message: test, data: null)',
      );
    });
  });
}
