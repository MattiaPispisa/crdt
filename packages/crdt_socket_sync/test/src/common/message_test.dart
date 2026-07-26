import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common/message.dart';
import 'package:test/test.dart';

void main() {
  group('MessageType', () {
    test('should have all expected message types', () {
      expect(MessageType.values, hasLength(9));
      expect(
        MessageType.values,
        containsAll([
          MessageType.handshakeRequest,
          MessageType.handshakeResponse,
          MessageType.change,
          MessageType.changes,
          MessageType.documentStatus,
          MessageType.documentStatusRequest,
          MessageType.ping,
          MessageType.pong,
          MessageType.error,
        ]),
      );
    });
  });

  group('Message factory methods (shared)', () {
    const documentId = 'test-doc-id';

    test('Message.ping() should create PingMessage', () {
      const timestamp = 1234567890;

      final message = Message.ping(
        documentId: documentId,
        timestamp: timestamp,
      );

      expect(message, isA<PingMessage>());
      expect(message.type, MessageType.ping);
      expect(message.documentId, documentId);
      expect((message as PingMessage).timestamp, timestamp);
    });

    test('Message.pong() should create PongMessage', () {
      const originalTimestamp = 1234567890;
      const responseTimestamp = 1234567900;

      final message = Message.pong(
        documentId: documentId,
        originalTimestamp: originalTimestamp,
        responseTimestamp: responseTimestamp,
      );

      expect(message, isA<PongMessage>());
      expect(message.type, MessageType.pong);
      expect(message.documentId, documentId);
      expect((message as PongMessage).originalTimestamp, originalTimestamp);
      expect(message.responseTimestamp, responseTimestamp);
    });

    test('Message.error() should create ErrorMessage', () {
      const code = 'TEST_ERROR';
      const errorMessage = 'Test error message';

      final message = Message.error(
        documentId: documentId,
        code: code,
        message: errorMessage,
      );

      expect(message, isA<ErrorMessage>());
      expect(message.type, MessageType.error);
      expect(message.documentId, documentId);
      expect((message as ErrorMessage).code, code);
      expect(message.message, errorMessage);
    });
  });

  group('PingMessage', () {
    const documentId = 'test-doc-id';
    const timestamp = 1234567890;

    test('should create with correct properties', () {
      const message = PingMessage(
        documentId: documentId,
        timestamp: timestamp,
      );

      expect(message.type, MessageType.ping);
      expect(message.documentId, documentId);
      expect(message.timestamp, timestamp);
    });

    test('should serialize to JSON correctly', () {
      const message = PingMessage(
        documentId: documentId,
        timestamp: timestamp,
      );

      final json = message.toJson();

      expect(json['type'], MessageType.ping.value);
      expect(json['documentId'], documentId);
      expect(json['timestamp'], timestamp);
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.ping.value,
        'documentId': documentId,
        'timestamp': timestamp,
      };

      final message = PingMessage.fromJson(json);

      expect(message.type, MessageType.ping);
      expect(message.documentId, documentId);
      expect(message.timestamp, timestamp);
    });

    test('should have correct toString representation', () {
      const message = PingMessage(
        documentId: documentId,
        timestamp: timestamp,
      );

      final string = message.toString();

      expect(string, contains('PingMessage'));
      expect(string, contains(timestamp.toString()));
      expect(string, contains(documentId));
    });

    test('should omit versionVector when not provided', () {
      const message = PingMessage(
        documentId: documentId,
        timestamp: timestamp,
      );

      expect(message.versionVector, isNull);
      expect(message.toJson().containsKey('versionVector'), isFalse);
    });

    test('should round-trip the reported versionVector', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(doc, 'list').insert(0, 'a');
      final versionVector = doc.getVersionVector();

      final message = PingMessage(
        documentId: documentId,
        timestamp: timestamp,
        versionVector: versionVector,
      );

      final json = message.toJson();
      expect(json['versionVector'], isNotNull);

      final restored = PingMessage.fromJson(json);
      expect(restored.versionVector, isNotNull);
      expect(
        restored.versionVector!.toBytes(),
        equals(versionVector.toBytes()),
      );
    });
  });

  group('PongMessage', () {
    const documentId = 'test-doc-id';
    const originalTimestamp = 1234567890;
    const responseTimestamp = 1234567900;

    test('should create with correct properties', () {
      const message = PongMessage(
        documentId: documentId,
        originalTimestamp: originalTimestamp,
        responseTimestamp: responseTimestamp,
      );

      expect(message.type, MessageType.pong);
      expect(message.documentId, documentId);
      expect(message.originalTimestamp, originalTimestamp);
      expect(message.responseTimestamp, responseTimestamp);
    });

    test('should serialize to JSON correctly', () {
      const message = PongMessage(
        documentId: documentId,
        originalTimestamp: originalTimestamp,
        responseTimestamp: responseTimestamp,
      );

      final json = message.toJson();

      expect(json['type'], MessageType.pong.value);
      expect(json['documentId'], documentId);
      expect(json['originalTimestamp'], originalTimestamp);
      expect(json['responseTimestamp'], responseTimestamp);
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.pong.value,
        'documentId': documentId,
        'originalTimestamp': originalTimestamp,
        'responseTimestamp': responseTimestamp,
      };

      final message = PongMessage.fromJson(json);

      expect(message.type, MessageType.pong);
      expect(message.documentId, documentId);
      expect(message.originalTimestamp, originalTimestamp);
      expect(message.responseTimestamp, responseTimestamp);
    });

    test('should have correct toString representation', () {
      const message = PongMessage(
        documentId: documentId,
        originalTimestamp: originalTimestamp,
        responseTimestamp: responseTimestamp,
      );

      final string = message.toString();

      expect(string, contains('PongMessage'));
      expect(string, contains(originalTimestamp.toString()));
      expect(string, contains(responseTimestamp.toString()));
      expect(string, contains(documentId));
    });
  });

  group('ErrorMessage', () {
    const documentId = 'test-doc-id';
    const code = 'TEST_ERROR';
    const errorMessage = 'Test error message';

    test('should create with correct properties', () {
      const message = ErrorMessage(
        documentId: documentId,
        code: code,
        message: errorMessage,
      );

      expect(message.type, MessageType.error);
      expect(message.documentId, documentId);
      expect(message.code, code);
      expect(message.message, errorMessage);
    });

    test('should serialize to JSON correctly', () {
      const message = ErrorMessage(
        documentId: documentId,
        code: code,
        message: errorMessage,
      );

      final json = message.toJson();

      expect(json['type'], MessageType.error.value);
      expect(json['documentId'], documentId);
      expect(json['code'], code);
      expect(json['message'], errorMessage);
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.error.value,
        'documentId': documentId,
        'code': code,
        'message': errorMessage,
      };

      final message = ErrorMessage.fromJson(json);

      expect(message.type, MessageType.error);
      expect(message.documentId, documentId);
      expect(message.code, code);
      expect(message.message, errorMessage);
    });

    test('should have correct toString representation', () {
      const message = ErrorMessage(
        documentId: documentId,
        code: code,
        message: errorMessage,
      );

      final string = message.toString();

      expect(string, contains('ErrorMessage'));
      expect(string, contains(code));
      expect(string, contains(errorMessage));
      expect(string, contains(documentId));
    });
  });

  group('Message.fromJson()', () {
    test('should deserialize PingMessage', () {
      final json = {
        'type': MessageType.ping.value,
        'documentId': 'test-doc',
        'timestamp': 1234567890,
      };

      final message = Message.fromJson(json);

      expect(message, isA<PingMessage>());
      expect(message!.type, MessageType.ping);
    });

    test('should deserialize PongMessage', () {
      final json = {
        'type': MessageType.pong.value,
        'documentId': 'test-doc',
        'originalTimestamp': 1234567890,
        'responseTimestamp': 1234567900,
      };

      final message = Message.fromJson(json);

      expect(message, isA<PongMessage>());
      expect(message!.type, MessageType.pong);
    });

    test('should deserialize ErrorMessage', () {
      final json = {
        'type': MessageType.error.value,
        'documentId': 'test-doc',
        'code': 'TEST_ERROR',
        'message': 'Test error',
      };

      final message = Message.fromJson(json);

      expect(message, isA<ErrorMessage>());
      expect(message!.type, MessageType.error);
    });

    test('should return null for server-client (sync) type codes', () {
      // Sync-protocol frames are decoded by SyncMessage.fromJson, not here;
      // Message.fromJson stays chainable by returning null for them.
      for (final type in [
        MessageType.handshakeRequest.value,
        MessageType.handshakeResponse.value,
        MessageType.change.value,
        MessageType.changes.value,
        MessageType.documentStatus.value,
        MessageType.documentStatusRequest.value,
      ]) {
        expect(
          Message.fromJson({'type': type, 'documentId': 'd'}),
          isNull,
          reason: 'type $type must not be decoded by Message.fromJson',
        );
      }
    });

    test('should return null for plugin type codes', () {
      expect(Message.fromJson({'type': 100, 'documentId': 'd'}), isNull);
    });
  });

  group('Message serialization', () {
    test('should serialize and deserialize correctly', () {
      const original = PingMessage(
        documentId: 'test-doc',
        timestamp: 1234567890,
      );

      final jsonString = original.serialize();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final restored = Message.fromJson(json);

      expect(restored, isA<PingMessage>());
      expect(restored!.documentId, original.documentId);
      expect((restored as PingMessage).timestamp, original.timestamp);
    });
  });

  group('Message toString()', () {
    test('should provide base toString for Message', () {
      const message = PingMessage(
        documentId: 'test-doc',
        timestamp: 1234567890,
      );

      // Test base Message toString (inherited behavior)
      expect(message.toString(), contains('PingMessage'));
    });
  });

  group('Message.getTypeOrNull()', () {
    test('should read the type code of a serialized core message', () {
      const message = PingMessage(documentId: 'test-doc', timestamp: 1);
      final data = utf8.encode(message.serialize());

      expect(Message.getTypeOrNull(data), MessageType.ping.value);
    });

    test('should read plugin type codes that fromJson cannot decode', () {
      // A plugin message (e.g. awareness uses codes 100+): unknown to the core
      // decoder, but its type code is still reported for diagnostics.
      final data = utf8.encode(jsonEncode({'type': 100, 'documentId': 'd'}));

      expect(Message.fromJson({'type': 100, 'documentId': 'd'}), isNull);
      expect(Message.getTypeOrNull(data), 100);
    });

    test('should return null for a malformed (non-JSON) frame', () {
      expect(Message.getTypeOrNull(utf8.encode('not json')), isNull);
      expect(Message.getTypeOrNull(const [0xff, 0xfe]), isNull);
    });

    test('should return null when type is missing or not an int', () {
      expect(
        Message.getTypeOrNull(utf8.encode(jsonEncode({'documentId': 'd'}))),
        isNull,
      );
      expect(
        Message.getTypeOrNull(utf8.encode(jsonEncode({'type': 'ping'}))),
        isNull,
      );
    });
  });
}
