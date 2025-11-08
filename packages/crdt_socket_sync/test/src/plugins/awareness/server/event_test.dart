import 'package:crdt_socket_sync/server.dart';
import 'package:test/test.dart';

void main() {
  group('ServerAwarenessEvent', () {
    const documentId = 'test-document-1';
    const clientId = 'client-1';

    test('should create event with all required properties', () {
      final event = ServerAwarenessEvent(
        type: ServerAwarenessEventType.clientJoined,
        documentId: documentId,
        clientId: clientId,
      );

      expect(event.type, ServerAwarenessEventType.clientJoined);
      expect(event.documentId, documentId);
      expect(event.clientId, clientId);
    });

    test('should create clientJoined event', () {
      final event = ServerAwarenessEvent(
        type: ServerAwarenessEventType.clientJoined,
        documentId: documentId,
        clientId: clientId,
      );

      expect(event.type, ServerAwarenessEventType.clientJoined);
    });

    test('should create clientUpdated event', () {
      final event = ServerAwarenessEvent(
        type: ServerAwarenessEventType.clientUpdated,
        documentId: documentId,
        clientId: clientId,
      );

      expect(event.type, ServerAwarenessEventType.clientUpdated);
    });

    test('should create clientLeft event', () {
      final event = ServerAwarenessEvent(
        type: ServerAwarenessEventType.clientLeft,
        documentId: documentId,
        clientId: clientId,
      );

      expect(event.type, ServerAwarenessEventType.clientLeft);
    });

    test('should have correct toString representation', () {
      final event = ServerAwarenessEvent(
        type: ServerAwarenessEventType.clientJoined,
        documentId: documentId,
        clientId: clientId,
      );

      final stringRep = event.toString();

      expect(stringRep, contains('ServerAwarenessEvent'));
      expect(stringRep, contains('clientJoined'));
      expect(stringRep, contains(documentId));
      expect(stringRep, contains(clientId));
    });

    test('toString should show different event types', () {
      final joinedEvent = ServerAwarenessEvent(
        type: ServerAwarenessEventType.clientJoined,
        documentId: documentId,
        clientId: clientId,
      );

      final updatedEvent = ServerAwarenessEvent(
        type: ServerAwarenessEventType.clientUpdated,
        documentId: documentId,
        clientId: clientId,
      );

      final leftEvent = ServerAwarenessEvent(
        type: ServerAwarenessEventType.clientLeft,
        documentId: documentId,
        clientId: clientId,
      );

      expect(joinedEvent.toString(), contains('clientJoined'));
      expect(updatedEvent.toString(), contains('clientUpdated'));
      expect(leftEvent.toString(), contains('clientLeft'));
    });

    test('should support different client IDs', () {
      final event1 = ServerAwarenessEvent(
        type: ServerAwarenessEventType.clientJoined,
        documentId: documentId,
        clientId: 'client-1',
      );

      final event2 = ServerAwarenessEvent(
        type: ServerAwarenessEventType.clientJoined,
        documentId: documentId,
        clientId: 'client-2',
      );

      expect(event1.clientId, 'client-1');
      expect(event2.clientId, 'client-2');
    });

    test('should support different document IDs', () {
      final event1 = ServerAwarenessEvent(
        type: ServerAwarenessEventType.clientJoined,
        documentId: 'doc-1',
        clientId: clientId,
      );

      final event2 = ServerAwarenessEvent(
        type: ServerAwarenessEventType.clientJoined,
        documentId: 'doc-2',
        clientId: clientId,
      );

      expect(event1.documentId, 'doc-1');
      expect(event2.documentId, 'doc-2');
    });
  });

  group('ServerAwarenessEventType', () {
    test('should have clientJoined type', () {
      expect(
        ServerAwarenessEventType.values,
        contains(ServerAwarenessEventType.clientJoined),
      );
    });

    test('should have clientUpdated type', () {
      expect(
        ServerAwarenessEventType.values,
        contains(ServerAwarenessEventType.clientUpdated),
      );
    });

    test('should have clientLeft type', () {
      expect(
        ServerAwarenessEventType.values,
        contains(ServerAwarenessEventType.clientLeft),
      );
    });

    test('should have exactly three event types', () {
      expect(ServerAwarenessEventType.values, hasLength(3));
    });

    test('should be usable in switch statements', () {
      const type = ServerAwarenessEventType.clientJoined;
      String result;

      switch (type) {
        case ServerAwarenessEventType.clientJoined:
          result = 'joined';
          break;
        case ServerAwarenessEventType.clientUpdated:
          result = 'updated';
          break;
        case ServerAwarenessEventType.clientLeft:
          result = 'left';
          break;
      }

      expect(result, 'joined');
    });
  });
}
