import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/message.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../utils/mock_handler.dart';
import '../utils/mock_operation.dart';

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

  group('Message factory methods', () {
    const documentId = 'test-doc-id';
    late CRDTDocument doc;
    late MockHandler handler;
    late MockOperation operation;

    setUp(() {
      doc = CRDTDocument();
      handler = MockHandler(doc);
      operation = MockOperation(handler);
    });

    test('Message.change() should create ChangeMessage', () {
      final change = Change(
        id: OperationId(
          PeerId.generate(),
          HybridLogicalClock(l: 1, c: 1),
        ),
        operation: operation,
        deps: {},
        author: PeerId.generate(),
      );

      final message = Message.change(
        documentId: documentId,
        change: change,
      );

      expect(message, isA<ChangeMessage>());
      expect(message.type, MessageType.change);
      expect(message.documentId, documentId);
      expect((message as ChangeMessage).change, change);
    });

    test('Message.snapshot() should create SnapshotMessage', () {
      final snapshot = Snapshot(
        id: 'test-snapshot',
        versionVector: VersionVector(
          {PeerId.generate(): HybridLogicalClock(l: 1, c: 1)},
        ),
        data: {'key': 'value'},
      );

      final message = Message.documentStatus(
        documentId: documentId,
        snapshot: snapshot,
        changes: [],
        versionVector: snapshot.versionVector,
      );

      expect(message, isA<DocumentStatusMessage>());
      expect(message.type, MessageType.documentStatus);
      expect(message.documentId, documentId);
      expect((message as DocumentStatusMessage).snapshot, snapshot);
    });

    test('Message.snapshotRequest() should create SnapshotRequestMessage', () {
      final versionVector = VersionVector({
        PeerId.generate(): HybridLogicalClock(l: 1, c: 1),
      });

      final message = Message.documentStatusRequest(
        documentId: documentId,
        versionVector: versionVector,
      );

      expect(message, isA<DocumentStatusRequestMessage>());
      expect(message.type, MessageType.documentStatusRequest);
      expect(message.documentId, documentId);
      expect((message as DocumentStatusRequestMessage).versionVector, versionVector);
    });

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

  group('HandshakeRequestMessage', () {
    const documentId = 'test-doc-id';
    final author = PeerId.generate();
    final versionVector = VersionVector({
      PeerId.generate(): HybridLogicalClock(l: 1, c: 1),
    });

    test('should create with correct properties', () {
      final message = HandshakeRequestMessage(
        documentId: documentId,
        author: author,
        versionVector: versionVector,
      );

      expect(message.type, MessageType.handshakeRequest);
      expect(message.documentId, documentId);
      expect(message.author, author);
      expect(message.versionVector, versionVector);
    });

    test('should serialize to JSON correctly', () {
      final message = HandshakeRequestMessage(
        documentId: documentId,
        author: author,
        versionVector: versionVector,
      );

      final json = message.toJson();

      expect(json['type'], MessageType.handshakeRequest.index);
      expect(json['documentId'], documentId);
      expect(json['author'], author.toString());
      expect(json['versionVector'], versionVector.toJson());
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.handshakeRequest.index,
        'documentId': documentId,
        'author': author.toString(),
        'versionVector': versionVector.toJson(),
      };

      final message = HandshakeRequestMessage.fromJson(json);

      expect(message.type, MessageType.handshakeRequest);
      expect(message.documentId, documentId);
      expect(message.author, author);
      expect(message.versionVector.toJson(), versionVector.toJson());
    });

    test('should have correct toString representation', () {
      final message = HandshakeRequestMessage(
        documentId: documentId,
        author: author,
        versionVector: versionVector,
      );

      final string = message.toString();

      expect(string, contains('HandshakeRequestMessage'));
      expect(string, contains(documentId));
      expect(string, contains(author.toString()));
    });
  });

  group('HandshakeResponseMessage', () {
    const documentId = 'test-doc-id';
    late CRDTDocument doc;
    late MockHandler handler;
    late MockOperation operation;
    late Snapshot snapshot;
    late List<Change> changes;

    setUp(() {
      doc = CRDTDocument();
      handler = MockHandler(doc);
      operation = MockOperation(handler);

      snapshot = Snapshot(
        id: 'test-snapshot',
        versionVector:
            VersionVector({PeerId.generate(): HybridLogicalClock(l: 1, c: 1)}),
        data: {'key': 'value'},
      );

      changes = [
        Change(
          id: OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1)),
          operation: operation,
          deps: {},
          author: PeerId.generate(),
        ),
        Change(
          id: OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 2)),
          operation: operation,
          deps: {},
          author: PeerId.generate(),
        ),
      ];
    });

    test('should create with snapshot and changes', () {
      final message = HandshakeResponseMessage(
        documentId: documentId,
        snapshot: snapshot,
        changes: changes,
        sessionId: 'test-session-id',
        versionVector: snapshot.versionVector,
      );

      expect(message.type, MessageType.handshakeResponse);
      expect(message.documentId, documentId);
      expect(message.snapshot, snapshot);
      expect(message.changes, changes);
    });

    test('should create with only snapshot', () {
      final message = HandshakeResponseMessage(
        documentId: documentId,
        snapshot: snapshot,
        sessionId: 'test-session-id',
        versionVector: snapshot.versionVector,
      );

      expect(message.snapshot, snapshot);
      expect(message.changes, isNull);
    });

    test('should create with only changes', () {
      final versionVector = VersionVector({});
      for (final change in changes) {
        versionVector.update(change.id.peerId, change.hlc);
      }

      final message = HandshakeResponseMessage(
        documentId: documentId,
        changes: changes,
        sessionId: 'test-session-id',
        versionVector: versionVector,
      );

      expect(message.snapshot, isNull);
      expect(message.changes, changes);
      expect(message.sessionId, 'test-session-id');
    });

    test('should serialize to JSON correctly', () {
      final message = HandshakeResponseMessage(
        documentId: documentId,
        snapshot: snapshot,
        changes: changes,
        sessionId: '5a2e1d55-74c7-453b-9256-1c5ffe3283b5',
        versionVector: snapshot.versionVector,
      );

      final json = message.toJson();

      expect(json['type'], MessageType.handshakeResponse.index);
      expect(json['documentId'], documentId);
      expect(json['snapshot'], snapshot.toJson());
      expect(json['changes'], changes.map((c) => c.toJson()).toList());
      expect(json['sessionId'], '5a2e1d55-74c7-453b-9256-1c5ffe3283b5');
      expect(json['versionVector'], snapshot.versionVector.toJson());
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.handshakeResponse.index,
        'documentId': documentId,
        'snapshot': snapshot.toJson(),
        'changes': changes.map((c) => c.toJson()).toList(),
        'sessionId': '5a2e1d55-74c7-453b-9256-1c5ffe3283b5',
        'versionVector': snapshot.versionVector.toJson(),
      };

      final message = HandshakeResponseMessage.fromJson(json);

      expect(message.type, MessageType.handshakeResponse);
      expect(message.documentId, documentId);
      expect(message.snapshot, isNotNull);
      expect(message.changes, hasLength(changes.length));
    });

    test('should handle null snapshot and changes in JSON', () {
      final emptyVV = VersionVector({});
      final json = {
        'type': MessageType.handshakeResponse.index,
        'documentId': documentId,
        'snapshot': null,
        'changes': null,
        'sessionId': '5a2e1d55-74c7-453b-9256-1c5ffe3283b5',
        'versionVector': emptyVV.toJson(),
      };

      final message = HandshakeResponseMessage.fromJson(json);

      expect(message.snapshot, isNull);
      expect(message.changes, isNull);
    });
  });

  group('ChangeMessage', () {
    const documentId = 'test-doc-id';
    late CRDTDocument doc;
    late MockHandler handler;
    late MockOperation operation;
    late Change change;

    setUp(() {
      doc = CRDTDocument();
      handler = MockHandler(doc);
      operation = MockOperation(handler);

      change = Change(
        id: OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        author: PeerId.generate(),
      );
    });

    test('should create with correct properties', () {
      final message = ChangeMessage(
        documentId: documentId,
        change: change,
      );

      expect(message.type, MessageType.change);
      expect(message.documentId, documentId);
      expect(message.change, change);
    });

    test('should serialize to JSON correctly', () {
      final message = ChangeMessage(
        documentId: documentId,
        change: change,
      );

      final json = message.toJson();

      expect(json['type'], MessageType.change.index);
      expect(json['documentId'], documentId);
      expect(json['change'], change.toJson());
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.change.index,
        'documentId': documentId,
        'change': change.toJson(),
      };

      final message = ChangeMessage.fromJson(json);

      expect(message.type, MessageType.change);
      expect(message.documentId, documentId);
      expect(message.change.id, change.id);
    });
  });

  group('SnapshotMessage', () {
    const documentId = 'test-doc-id';
    final snapshot = Snapshot(
      id: 'test-snapshot',
      versionVector:
          VersionVector({PeerId.generate(): HybridLogicalClock(l: 1, c: 1)}),
      data: {'key': 'value'},
    );

    test('should create with correct properties', () {
      final message = DocumentStatusMessage(
        documentId: documentId,
        snapshot: snapshot,
        versionVector: snapshot.versionVector,
      );

      expect(message.type, MessageType.documentStatus);
      expect(message.documentId, documentId);
      expect(message.snapshot, snapshot);
    });

    test('should serialize to JSON correctly', () {
      final message = DocumentStatusMessage(
        documentId: documentId,
        snapshot: snapshot,
        versionVector: snapshot.versionVector,
      );

      final json = message.toJson();

      expect(json['type'], MessageType.documentStatus.index);
      expect(json['documentId'], documentId);
      expect(json['snapshot'], snapshot.toJson());
      expect(json['versionVector'], snapshot.versionVector.toJson());
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.documentStatus.index,
        'documentId': documentId,
        'snapshot': snapshot.toJson(),
        'versionVector': snapshot.versionVector.toJson(),
      };

      final message = DocumentStatusMessage.fromJson(json);

      expect(message.type, MessageType.documentStatus);
      expect(message.documentId, documentId);
      expect(message.snapshot, isNotNull);
    });
  });

  group('SnapshotRequestMessage', () {
    const documentId = 'test-doc-id';
    final versionVector = VersionVector({
      PeerId.generate(): HybridLogicalClock(l: 1, c: 1),
    });

    test('should create with correct properties', () {
      final message = DocumentStatusRequestMessage(
        documentId: documentId,
        versionVector: versionVector,
      );

      expect(message.type, MessageType.documentStatusRequest);
      expect(message.documentId, documentId);
      expect(message.versionVector, versionVector);
    });

    test('should serialize to JSON correctly', () {
      final message = DocumentStatusRequestMessage(
        documentId: documentId,
        versionVector: versionVector,
      );

      final json = message.toJson();

      expect(json['type'], MessageType.documentStatusRequest.index);
      expect(json['documentId'], documentId);
      expect(json['versionVector'], versionVector.toJson());
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.documentStatusRequest.index,
        'documentId': documentId,
        'versionVector': versionVector.toJson(),
      };

      final message = DocumentStatusRequestMessage.fromJson(json);

      expect(message.type, MessageType.documentStatusRequest);
      expect(message.documentId, documentId);
      expect(message.versionVector?.toJson(), versionVector.toJson());
    });

    test('should handle null versionVector', () {
      final message = DocumentStatusRequestMessage(
        documentId: documentId,
        versionVector: null,
      );

      expect(message.versionVector, isNull);
      
      final json = message.toJson();
      expect(json['versionVector'], isNull);
      
      final deserialized = DocumentStatusRequestMessage.fromJson(json);
      expect(deserialized.versionVector, isNull);
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

      expect(json['type'], MessageType.ping.index);
      expect(json['documentId'], documentId);
      expect(json['timestamp'], timestamp);
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.ping.index,
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

      expect(json['type'], MessageType.pong.index);
      expect(json['documentId'], documentId);
      expect(json['originalTimestamp'], originalTimestamp);
      expect(json['responseTimestamp'], responseTimestamp);
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.pong.index,
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

      expect(json['type'], MessageType.error.index);
      expect(json['documentId'], documentId);
      expect(json['code'], code);
      expect(json['message'], errorMessage);
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.error.index,
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
    late CRDTDocument doc;
    late MockHandler handler;
    late MockOperation operation;

    setUp(() {
      doc = CRDTDocument();
      handler = MockHandler(doc);
      operation = MockOperation(handler);
    });

    test('should deserialize HandshakeRequestMessage', () {
      final json = {
        'type': MessageType.handshakeRequest.index,
        'documentId': 'test-doc',
        'author': PeerId.generate().toString(),
        'versionVector': {'vector': <String,dynamic>{}},
      };

      final message = Message.fromJson(json);

      expect(message, isA<HandshakeRequestMessage>());
      expect(message!.type, MessageType.handshakeRequest);
    });

    test('should deserialize HandshakeResponseMessage', () {
      final emptyVV = VersionVector({});
      final json = {
        'type': MessageType.handshakeResponse.index,
        'documentId': 'test-doc',
        'snapshot': null,
        'changes': null,
        'sessionId': '5a2e1d55-74c7-453b-9256-1c5ffe3283b5',
        'versionVector': emptyVV.toJson(),
      };

      final message = Message.fromJson(json);

      expect(message, isA<HandshakeResponseMessage>());
      expect(message!.type, MessageType.handshakeResponse);
    });

    test('should deserialize ChangeMessage', () {
      final change = Change(
        id: OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        author: PeerId.generate(),
      );
      final json = {
        'type': MessageType.change.index,
        'documentId': 'test-doc',
        'change': change.toJson(),
      };

      final message = Message.fromJson(json);

      expect(message, isA<ChangeMessage>());
      expect(message!.type, MessageType.change);
    });

    test('should deserialize SnapshotMessage', () {
      final snapshot = Snapshot(
        id: 'test-snapshot',
        versionVector:
            VersionVector({PeerId.generate(): HybridLogicalClock(l: 1, c: 1)}),
        data: {'key': 'value'},
      );
      final json = {
        'type': MessageType.documentStatus.index,
        'documentId': 'test-doc',
        'snapshot': snapshot.toJson(),
        'versionVector': snapshot.versionVector.toJson(),
      };

      final message = Message.fromJson(json);

      expect(message, isA<DocumentStatusMessage>());
      expect(message!.type, MessageType.documentStatus);
    });

    test('should deserialize SnapshotRequestMessage', () {
      final json = {
        'type': MessageType.documentStatusRequest.index,
        'documentId': 'test-doc',
        'version': <String>[],
      };

      final message = Message.fromJson(json);

      expect(message, isA<DocumentStatusRequestMessage>());
      expect(message!.type, MessageType.documentStatusRequest);
    });

    test('should deserialize PingMessage', () {
      final json = {
        'type': MessageType.ping.index,
        'documentId': 'test-doc',
        'timestamp': 1234567890,
      };

      final message = Message.fromJson(json);

      expect(message, isA<PingMessage>());
      expect(message!.type, MessageType.ping);
    });

    test('should deserialize PongMessage', () {
      final json = {
        'type': MessageType.pong.index,
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
        'type': MessageType.error.index,
        'documentId': 'test-doc',
        'code': 'TEST_ERROR',
        'message': 'Test error',
      };

      final message = Message.fromJson(json);

      expect(message, isA<ErrorMessage>());
      expect(message!.type, MessageType.error);
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

    test('should handle complex message serialization', () {
      final doc = CRDTDocument();
      final handler = MockHandler(doc);
      final operation = MockOperation(handler);

      final change = Change(
        id: OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        author: PeerId.generate(),
      );
      final original = ChangeMessage(
        documentId: 'complex-doc-id',
        change: change,
      );

      final jsonString = original.serialize();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final restored = Message.fromJson(json);

      expect(restored, isA<ChangeMessage>());
      expect(restored!.documentId, original.documentId);
      expect((restored as ChangeMessage).change.id, change.id);
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
}
