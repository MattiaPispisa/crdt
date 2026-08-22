import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/common/common/message.dart';
import 'package:crdt_socket_sync/src/server_client/common/message.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../../utils/mock_handler.dart';
import '../../utils/mock_operation.dart';

String _encCh(Change c) => base64Encode(c.toBytes());
String _encVV(VersionVector vv) => base64Encode(vv.toBytes());
String _encSnap(Snapshot s) => base64Encode(s.toBytes());

void main() {
  group('SyncMessage factory methods', () {
    const documentId = 'test-doc-id';
    late CRDTDocument doc;
    late MockHandler handler;
    late MockOperation operation;

    setUp(() {
      doc = CRDTDocument();
      handler = MockHandler(doc);
      operation = MockOperation(handler);
    });

    test('SyncMessage.change() should create ChangeMessage', () {
      final peer = PeerId.generate();
      final change = Change(
        id: OperationId(
          peer,
          HybridLogicalClock(l: 1, c: 1),
        ),
        operation: operation,
        deps: {},
        author: peer,
      );

      final message = SyncMessage.change(
        documentId: documentId,
        change: change,
      );

      expect(message, isA<ChangeMessage>());
      expect(message.type, MessageType.change);
      expect(message.documentId, documentId);
      expect((message as ChangeMessage).change, change);
    });

    test('SyncMessage.documentStatus() creates a DocumentStatusMessage', () {
      final snapshot = Snapshot(
        id: 'test-snapshot',
        versionVector: VersionVector(
          {PeerId.generate(): HybridLogicalClock(l: 1, c: 1)},
        ),
        data: {
          'key': Uint8List.fromList([1, 2, 3]),
        },
      );

      final message = SyncMessage.documentStatus(
        documentId: documentId,
        snapshot: snapshot,
        changes: const [],
        versionVector: snapshot.versionVector,
      );

      expect(message, isA<DocumentStatusMessage>());
      expect(message.type, MessageType.documentStatus);
      expect(message.documentId, documentId);
      expect((message as DocumentStatusMessage).snapshot, snapshot);
    });

    test(
        'SyncMessage.documentStatusRequest() should create '
        'DocumentStatusRequestMessage', () {
      final versionVector = VersionVector({
        PeerId.generate(): HybridLogicalClock(l: 1, c: 1),
      });

      final message = SyncMessage.documentStatusRequest(
        documentId: documentId,
        versionVector: versionVector,
      );

      expect(message, isA<DocumentStatusRequestMessage>());
      expect(message.type, MessageType.documentStatusRequest);
      expect(message.documentId, documentId);
      expect(
        (message as DocumentStatusRequestMessage).versionVector,
        versionVector,
      );
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

      expect(json['type'], MessageType.handshakeRequest.value);
      expect(json['documentId'], documentId);
      expect(json['author'], author.toString());
      expect(json['versionVector'], _encVV(versionVector));
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.handshakeRequest.value,
        'documentId': documentId,
        'author': author.toString(),
        'versionVector': _encVV(versionVector),
      };

      final message = HandshakeRequestMessage.fromJson(json);

      expect(message.type, MessageType.handshakeRequest);
      expect(message.documentId, documentId);
      expect(message.author, author);
      expect(message.versionVector.toBytes(), versionVector.toBytes());
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
        data: {
          'key': Uint8List.fromList([1, 2, 3]),
        },
      );

      final peer1 = PeerId.generate();
      final peer2 = PeerId.generate();
      changes = [
        Change(
          id: OperationId(peer1, HybridLogicalClock(l: 1, c: 1)),
          operation: operation,
          deps: {},
          author: peer1,
        ),
        Change(
          id: OperationId(peer2, HybridLogicalClock(l: 1, c: 2)),
          operation: operation,
          deps: {},
          author: peer2,
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

      expect(json['type'], MessageType.handshakeResponse.value);
      expect(json['documentId'], documentId);
      expect(json['snapshot'], _encSnap(snapshot));
      expect(json['changes'], changes.map(_encCh).toList());
      expect(json['sessionId'], '5a2e1d55-74c7-453b-9256-1c5ffe3283b5');
      expect(json['versionVector'], _encVV(snapshot.versionVector));
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.handshakeResponse.value,
        'documentId': documentId,
        'snapshot': _encSnap(snapshot),
        'changes': changes.map(_encCh).toList(),
        'sessionId': '5a2e1d55-74c7-453b-9256-1c5ffe3283b5',
        'versionVector': _encVV(snapshot.versionVector),
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
        'type': MessageType.handshakeResponse.value,
        'documentId': documentId,
        'snapshot': null,
        'changes': null,
        'sessionId': '5a2e1d55-74c7-453b-9256-1c5ffe3283b5',
        'versionVector': _encVV(emptyVV),
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

      final peer = PeerId.generate();
      change = Change(
        id: OperationId(peer, HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        author: peer,
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

      expect(json['type'], MessageType.change.value);
      expect(json['documentId'], documentId);
      expect(json['change'], _encCh(change));
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.change.value,
        'documentId': documentId,
        'change': _encCh(change),
      };

      final message = ChangeMessage.fromJson(json);

      expect(message.type, MessageType.change);
      expect(message.documentId, documentId);
      expect(message.change.id, change.id);
    });
  });

  group('DocumentStatusMessage', () {
    const documentId = 'test-doc-id';
    final snapshot = Snapshot(
      id: 'test-snapshot',
      versionVector:
          VersionVector({PeerId.generate(): HybridLogicalClock(l: 1, c: 1)}),
      data: {
        'key': Uint8List.fromList([1, 2, 3]),
      },
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

      expect(json['type'], MessageType.documentStatus.value);
      expect(json['documentId'], documentId);
      expect(json['snapshot'], _encSnap(snapshot));
      expect(json['versionVector'], _encVV(snapshot.versionVector));
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.documentStatus.value,
        'documentId': documentId,
        'snapshot': _encSnap(snapshot),
        'versionVector': _encVV(snapshot.versionVector),
      };

      final message = DocumentStatusMessage.fromJson(json);

      expect(message.type, MessageType.documentStatus);
      expect(message.documentId, documentId);
      expect(message.snapshot, isNotNull);
    });
  });

  group('DocumentStatusRequestMessage', () {
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

      expect(json['type'], MessageType.documentStatusRequest.value);
      expect(json['documentId'], documentId);
      expect(json['versionVector'], _encVV(versionVector));
    });

    test('should deserialize from JSON correctly', () {
      final json = {
        'type': MessageType.documentStatusRequest.value,
        'documentId': documentId,
        'versionVector': _encVV(versionVector),
      };

      final message = DocumentStatusRequestMessage.fromJson(json);

      expect(message.type, MessageType.documentStatusRequest);
      expect(message.documentId, documentId);
      expect(message.versionVector?.toBytes(), versionVector.toBytes());
    });

    test('should handle null versionVector', () {
      const message = DocumentStatusRequestMessage(
        documentId: documentId,
      );

      expect(message.versionVector, isNull);

      final json = message.toJson();
      expect(json['versionVector'], isNull);

      final deserialized = DocumentStatusRequestMessage.fromJson(json);
      expect(deserialized.versionVector, isNull);
    });
  });

  group('SyncMessage.fromJson()', () {
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
        'type': MessageType.handshakeRequest.value,
        'documentId': 'test-doc',
        'author': PeerId.generate().toString(),
        'versionVector': _encVV(VersionVector({})),
      };

      final message = SyncMessage.fromJson(json);

      expect(message, isA<HandshakeRequestMessage>());
      expect(message!.type, MessageType.handshakeRequest);
    });

    test('should deserialize HandshakeResponseMessage', () {
      final emptyVV = VersionVector({});
      final json = {
        'type': MessageType.handshakeResponse.value,
        'documentId': 'test-doc',
        'snapshot': null,
        'changes': null,
        'sessionId': '5a2e1d55-74c7-453b-9256-1c5ffe3283b5',
        'versionVector': _encVV(emptyVV),
      };

      final message = SyncMessage.fromJson(json);

      expect(message, isA<HandshakeResponseMessage>());
      expect(message!.type, MessageType.handshakeResponse);
    });

    test('should deserialize ChangeMessage', () {
      final peer = PeerId.generate();
      final change = Change(
        id: OperationId(peer, HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        author: peer,
      );
      final json = {
        'type': MessageType.change.value,
        'documentId': 'test-doc',
        'change': _encCh(change),
      };

      final message = SyncMessage.fromJson(json);

      expect(message, isA<ChangeMessage>());
      expect(message!.type, MessageType.change);
    });

    test('should deserialize DocumentStatusMessage', () {
      final snapshot = Snapshot(
        id: 'test-snapshot',
        versionVector:
            VersionVector({PeerId.generate(): HybridLogicalClock(l: 1, c: 1)}),
        data: {
          'key': Uint8List.fromList([1, 2, 3]),
        },
      );
      final json = {
        'type': MessageType.documentStatus.value,
        'documentId': 'test-doc',
        'snapshot': _encSnap(snapshot),
        'versionVector': _encVV(snapshot.versionVector),
      };

      final message = SyncMessage.fromJson(json);

      expect(message, isA<DocumentStatusMessage>());
      expect(message!.type, MessageType.documentStatus);
    });

    test('should deserialize DocumentStatusRequestMessage', () {
      final json = {
        'type': MessageType.documentStatusRequest.value,
        'documentId': 'test-doc',
      };

      final message = SyncMessage.fromJson(json);

      expect(message, isA<DocumentStatusRequestMessage>());
      expect(message!.type, MessageType.documentStatusRequest);
    });

    test('should return null for a shared (ping/pong/error) type code', () {
      expect(
        SyncMessage.fromJson({
          'type': MessageType.ping.value,
          'documentId': 'test-doc',
          'timestamp': 1,
        }),
        isNull,
      );
    });

    test('should return null for a type code outside the sync protocol', () {
      expect(
        SyncMessage.fromJson({'type': 100, 'documentId': 'd'}),
        isNull,
      );
    });
  });

  group('SyncMessage serialization', () {
    test('should serialize and deserialize a ChangeMessage', () {
      final doc = CRDTDocument();
      final handler = MockHandler(doc);
      final operation = MockOperation(handler);

      final peer = PeerId.generate();
      final change = Change(
        id: OperationId(peer, HybridLogicalClock(l: 1, c: 1)),
        operation: operation,
        deps: {},
        author: peer,
      );
      final original = ChangeMessage(
        documentId: 'complex-doc-id',
        change: change,
      );

      final jsonString = original.serialize();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final restored = SyncMessage.fromJson(json);

      expect(restored, isA<ChangeMessage>());
      expect(restored!.documentId, original.documentId);
      expect((restored as ChangeMessage).change.id, change.id);
    });
  });
}
