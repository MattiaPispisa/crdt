import 'package:crdt_socket_sync/server.dart';
import 'package:test/test.dart';

void main() {
  group('AwarenessMessage', () {
    const documentId = 'test-document-1';

    group('AwarenessUpdateMessage', () {
      test('should serialize to JSON correctly', () {
        const state = ClientAwareness(
          clientId: 'client-1',
          metadata: {'name': 'John', 'cursor': 42},
        );

        const message = AwarenessUpdateMessage(
          state: state,
          documentId: documentId,
        );

        final json = message.toJson();

        expect(json['type'], AwarenessMessageType.awarenessUpdate.value);
        expect(json['documentId'], documentId);
        expect(json['state'], isA<Map<String, dynamic>>());
        expect((json['state'] as Map<String, dynamic>)['clientId'], 'client-1');
        expect(
          (json['state'] as Map<String, dynamic>)['metadata'],
          {'name': 'John', 'cursor': 42},
        );
      });

      test('should deserialize from JSON correctly', () {
        final json = {
          'type': AwarenessMessageType.awarenessUpdate.value,
          'documentId': documentId,
          'state': {
            'clientId': 'client-1',
            'metadata': {'name': 'John', 'cursor': 42},
          },
        };

        final message = AwarenessUpdateMessage.fromJson(json);

        expect(message.documentId, documentId);
        expect(message.type, AwarenessMessageType.awarenessUpdate);
        expect(message.state.clientId, 'client-1');
        expect(message.state.metadata, {'name': 'John', 'cursor': 42});
      });

      test('should round-trip through JSON', () {
        const original = AwarenessUpdateMessage(
          state: ClientAwareness(
            clientId: 'client-1',
            metadata: {'name': 'John', 'cursor': 42},
          ),
          documentId: documentId,
        );

        final json = original.toJson();
        final deserialized = AwarenessUpdateMessage.fromJson(json);

        expect(deserialized.documentId, original.documentId);
        expect(deserialized.type, original.type);
        expect(deserialized.state, original.state);
      });

      test('should have correct toString', () {
        const message = AwarenessUpdateMessage(
          state: ClientAwareness(
            clientId: 'client-1',
            metadata: {'name': 'John'},
          ),
          documentId: documentId,
        );

        final stringRep = message.toString();

        expect(stringRep, contains('AwarenessUpdateMessage'));
        expect(stringRep, contains(documentId));
      });
    });

    group('AwarenessQueryMessage', () {
      test('should serialize to JSON correctly', () {
        const message = AwarenessQueryMessage(documentId: documentId);

        final json = message.toJson();

        expect(json['type'], AwarenessMessageType.awarenessQuery.value);
        expect(json['documentId'], documentId);
        expect(json.keys, hasLength(2));
      });

      test('should deserialize from JSON correctly', () {
        final json = {
          'type': AwarenessMessageType.awarenessQuery.value,
          'documentId': documentId,
        };

        final message = AwarenessQueryMessage.fromJson(json);

        expect(message.documentId, documentId);
        expect(message.type, AwarenessMessageType.awarenessQuery);
      });

      test('should round-trip through JSON', () {
        const original = AwarenessQueryMessage(documentId: documentId);

        final json = original.toJson();
        final deserialized = AwarenessQueryMessage.fromJson(json);

        expect(deserialized.documentId, original.documentId);
        expect(deserialized.type, original.type);
      });

      test('should have correct toString', () {
        const message = AwarenessQueryMessage(documentId: documentId);

        final stringRep = message.toString();

        expect(stringRep, contains('AwarenessQueryMessage'));
        expect(stringRep, contains(documentId));
      });
    });

    group('AwarenessStateMessage', () {
      test('should serialize to JSON correctly', () {
        const awareness = DocumentAwareness(
          documentId: documentId,
          states: {
            'client-1': ClientAwareness(
              clientId: 'client-1',
              metadata: {'name': 'John'},
            ),
            'client-2': ClientAwareness(
              clientId: 'client-2',
              metadata: {'name': 'Jane'},
            ),
          },
        );

        const message = AwarenessStateMessage(
          awareness: awareness,
          documentId: documentId,
        );

        final json = message.toJson();

        expect(json['type'], AwarenessMessageType.awarenessState.value);
        expect(json['documentId'], documentId);
        expect(json['awareness'], isA<Map<String, dynamic>>());
        expect(
          (json['awareness'] as Map<String, dynamic>)['documentId'],
          documentId,
        );
        expect(
          (json['awareness'] as Map<String, dynamic>)['states'],
          isA<Map<String, dynamic>>(),
        );
        expect(
          ((json['awareness'] as Map<String, dynamic>)['states']
                  as Map<String, dynamic>)
              .keys,
          containsAll(['client-1', 'client-2']),
        );
      });

      test('should deserialize from JSON correctly', () {
        final json = {
          'type': AwarenessMessageType.awarenessState.value,
          'documentId': documentId,
          'awareness': {
            'documentId': documentId,
            'states': {
              'client-1': {
                'clientId': 'client-1',
                'metadata': {'name': 'John'},
              },
              'client-2': {
                'clientId': 'client-2',
                'metadata': {'name': 'Jane'},
              },
            },
          },
        };

        final message = AwarenessStateMessage.fromJson(json);

        expect(message.documentId, documentId);
        expect(message.type, AwarenessMessageType.awarenessState);
        expect(message.awareness.documentId, documentId);
        expect(
          message.awareness.states.keys,
          containsAll(['client-1', 'client-2']),
        );
        expect(
          message.awareness.states['client-1']?.metadata,
          {'name': 'John'},
        );
        expect(
          message.awareness.states['client-2']?.metadata,
          {'name': 'Jane'},
        );
      });

      test('should round-trip through JSON', () {
        const original = AwarenessStateMessage(
          awareness: DocumentAwareness(
            documentId: documentId,
            states: {
              'client-1': ClientAwareness(
                clientId: 'client-1',
                metadata: {'name': 'John'},
              ),
            },
          ),
          documentId: documentId,
        );

        final json = original.toJson();
        final deserialized = AwarenessStateMessage.fromJson(json);

        expect(deserialized.documentId, original.documentId);
        expect(deserialized.type, original.type);
        expect(deserialized.awareness, original.awareness);
      });

      test('should have correct toString', () {
        const message = AwarenessStateMessage(
          awareness: DocumentAwareness(
            documentId: documentId,
            states: {},
          ),
          documentId: documentId,
        );

        final stringRep = message.toString();

        expect(stringRep, contains('AwarenessStateMessage'));
        expect(stringRep, contains(documentId));
      });

      test('should handle empty states', () {
        const message = AwarenessStateMessage(
          awareness: DocumentAwareness(
            documentId: documentId,
            states: {},
          ),
          documentId: documentId,
        );

        final json = message.toJson();
        final deserialized = AwarenessStateMessage.fromJson(json);

        expect(deserialized.awareness.states, isEmpty);
      });
    });

    group('AwarenessMessage.fromJson', () {
      test('should deserialize AwarenessUpdateMessage', () {
        final json = {
          'type': AwarenessMessageType.awarenessUpdate.value,
          'documentId': documentId,
          'state': {
            'clientId': 'client-1',
            'metadata': {'name': 'John'},
          },
        };

        final message = AwarenessMessage.fromJson(json);

        expect(message, isA<AwarenessUpdateMessage>());
        expect(message?.documentId, documentId);
      });

      test('should deserialize AwarenessQueryMessage', () {
        final json = {
          'type': AwarenessMessageType.awarenessQuery.value,
          'documentId': documentId,
        };

        final message = AwarenessMessage.fromJson(json);

        expect(message, isA<AwarenessQueryMessage>());
        expect(message?.documentId, documentId);
      });

      test('should deserialize AwarenessStateMessage', () {
        final json = {
          'type': AwarenessMessageType.awarenessState.value,
          'documentId': documentId,
          'awareness': {
            'documentId': documentId,
            'states': <String, dynamic>{},
          },
        };

        final message = AwarenessMessage.fromJson(json);

        expect(message, isA<AwarenessStateMessage>());
        expect(message?.documentId, documentId);
      });

      test('should return null for invalid type (too low)', () {
        final json = {
          'type': 99,
          'documentId': documentId,
        };

        final message = AwarenessMessage.fromJson(json);

        expect(message, isNull);
      });

      test('should return null for invalid type (too high)', () {
        final json = {
          'type': 103,
          'documentId': documentId,
        };

        final message = AwarenessMessage.fromJson(json);

        expect(message, isNull);
      });
    });

    group('AwarenessMessageType', () {
      test('should have correct values', () {
        expect(AwarenessMessageType.awarenessUpdate.value, 100);
        expect(AwarenessMessageType.awarenessQuery.value, 101);
        expect(AwarenessMessageType.awarenessState.value, 102);
      });

      test('should be accessible by index', () {
        expect(
          AwarenessMessageType.values[0],
          AwarenessMessageType.awarenessUpdate,
        );
        expect(
          AwarenessMessageType.values[1],
          AwarenessMessageType.awarenessQuery,
        );
        expect(
          AwarenessMessageType.values[2],
          AwarenessMessageType.awarenessState,
        );
      });
    });
  });
}
