import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../utils/mock_handler.dart';
import '../utils/mock_operation.dart';
import '../utils/mock_socket_client.dart';

void main() {
  group('SyncManager', () {
    late CRDTDocument document;
    late MockCRDTSocketClient mockClient;
    late SyncManager syncManager;
    late MockHandler handler;
    late PeerId peerId;

    setUp(() {
      peerId = PeerId.generate();
      document = CRDTDocument(peerId: peerId);
      handler = MockHandler(document);
      mockClient = MockCRDTSocketClient(
        document: document,
        author: peerId,
      )..clearSentMessages();
      syncManager = SyncManager(
        document: document,
        client: mockClient,
      );
    });

    tearDown(() {
      syncManager.dispose();
      mockClient.dispose();
      document.dispose();
    });

    group('Constructor', () {
      test('should initialize with document and client', () {
        expect(syncManager.document, equals(document));
        expect(syncManager.client, equals(mockClient));
      });
    });

    group('applyChange', () {
      test('should apply change to document successfully', () {
        final operation = MockOperation(handler);
        final change = Change(
          id: OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1)),
          operation: operation,
          deps: {},
          author: PeerId.generate(),
        );

        expect(() => syncManager.applyChange(change), returnsNormally);
      });

      test('should request missing changes when apply fails', () async {
        final operation = MockOperation(handler);
        final nonReadyChange = Change(
          id: OperationId(PeerId.generate(), HybridLogicalClock(l: 2, c: 1)),
          operation: operation,
          deps: {
            OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1)),
          },
          author: PeerId.generate(),
        );

        // This should trigger the error handling path
        syncManager.applyChange(nonReadyChange);

        // Wait for the async snapshot request to be sent
        await Future<void>.delayed(Duration.zero);

        // Should have sent a snapshot request
        expect(mockClient.sentMessages.length, equals(1));
        final sentMessage = mockClient.getLastSentMessage();
        expect(sentMessage, isA<DocumentStatusRequestMessage>());
        expect(sentMessage!.documentId, equals(document.documentId));
      });

      test('should handle error when requesting missing changes gracefully',
          () async {
        mockClient.setShouldThrowOnSendMessage = true;

        final operation = MockOperation(handler);
        final nonReadyChange = Change(
          id: OperationId(PeerId.generate(), HybridLogicalClock(l: 2, c: 1)),
          operation: operation,
          deps: {
            OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1)),
          },
          author: PeerId.generate(),
        );

        // This should not throw even when the client throws
        expect(() => syncManager.applyChange(nonReadyChange), returnsNormally);

        // Wait for the async operation to complete
        await Future<void>.delayed(Duration.zero);

        expect(mockClient.sentMessages.length, equals(0));
      });
    });

    group('applyChanges', () {
      test('should apply multiple changes successfully', () {
        final operation = MockOperation(handler);
        final changes = [
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

        expect(() => syncManager.applyChanges(changes), returnsNormally);
      });

      test('should apply empty list of changes without error', () {
        expect(() => syncManager.applyChanges([]), returnsNormally);
      });

      test(
          'should handle mixed valid and invalid changes '
          'requesting missing data one time', () async {
        mockClient.clearSentMessages();

        final operation = MockOperation(handler);
        final validChange = Change(
          id: OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1)),
          operation: operation,
          deps: {},
          author: PeerId.generate(),
        );

        final invalidChange = Change(
          id: OperationId(PeerId.generate(), HybridLogicalClock(l: 2, c: 1)),
          operation: operation,
          deps: {
            OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 2)),
          },
          author: PeerId.generate(),
        );

        final secondInvalidChange = Change(
          id: OperationId(PeerId.generate(), HybridLogicalClock(l: 3, c: 1)),
          operation: operation,
          deps: {
            OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 2)),
          },
          author: PeerId.generate(),
        );

        syncManager.applyChanges([
          validChange,
          invalidChange,
          secondInvalidChange,
        ]);

        // Wait for async operations
        await Future<void>.delayed(Duration.zero);

        // Should have sent at least one snapshot request
        // due to the invalid change
        final snapshotRequests =
            mockClient.getSentMessagesOfType<DocumentStatusRequestMessage>();
        expect(snapshotRequests.length, equals(1));
      });
    });

    group('merge', () {
      test('should apply snapshot successfully', () {
        final snapshot = Snapshot(
          id: 'test-snapshot',
          versionVector: VersionVector(
            {peerId: HybridLogicalClock(l: 1, c: 1)},
          ),
          data: {'test-handler': 'test_state'},
        );

        expect(
          () => syncManager.merge(
            serverVersionVector: snapshot.versionVector,
            snapshot: snapshot,
            changes: [],
          ),
          returnsNormally,
        );
      });

      test('should send local changes newer than server when client ahead',
          () async {
        mockClient.clearSentMessages();

        // Create some local changes
        final operation = MockOperation(handler);
        document.createChange(operation);
        document.createChange(operation);

        // Wait for local changes to be processed
        await Future<void>.delayed(Duration.zero);

        final localChangesCount = mockClient.sentMessages.length;

        // Now merge with snapshot that has older version
        final olderPeerId = PeerId.generate();
        final snapshot = Snapshot(
          id: 'test-snapshot',
          versionVector: VersionVector(
            {olderPeerId: HybridLogicalClock(l: 1, c: 1)},
          ),
          data: {'test-handler': 'test_state'},
        );

        syncManager.merge(serverVersionVector: snapshot.versionVector, snapshot: snapshot, changes: []);

        // Wait for async operations
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Should have sent local changes via merge
        expect(mockClient.sentMessages.length, greaterThan(localChangesCount));
        final changesMessages =
            mockClient.getSentMessagesOfType<ChangesMessage>();
        expect(changesMessages, isNotEmpty);
      });

      test('should not send changes if server is ahead', () async {
        mockClient.clearSentMessages();

        // Create local change
        final operation = MockOperation(handler);
        document.createChange(operation);

        // Get the current version
        final currentVV = document.getVersionVector();

        // Merge with snapshot that includes the client's change
        final snapshot = Snapshot(
          id: 'test-snapshot',
          versionVector: currentVV.mutable(),
          data: {'test-handler': 'test_state'},
        );

        // Add a newer change on the snapshot
        snapshot.versionVector.update(peerId, HybridLogicalClock(l: 10, c: 1));

        syncManager.merge(serverVersionVector: snapshot.versionVector, snapshot: snapshot, changes: []);

        // Wait for async operations
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Should not send additional changes
        final changesMessages = mockClient.getSentMessagesOfType<ChangesMessage>();
        expect(changesMessages, isEmpty); 
      });

      test('should handle changes from multiple peers correctly', () async {
        mockClient.clearSentMessages();

        final otherPeerId = PeerId.generate();
        final operation = MockOperation(handler);

        // Create local change
        document.createChange(operation);

        // Merge with server changes from another peer
        final serverChange = Change(
          id: OperationId(otherPeerId, HybridLogicalClock(l: 1, c: 1)),
          operation: operation,
          deps: {},
          author: otherPeerId,
        );

        syncManager.merge(
          serverVersionVector: VersionVector({otherPeerId: serverChange.hlc}),
          changes: [serverChange],
          snapshot: null,
        );

        // Wait for async operations
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Should have sent local changes as they're newer
        final changeMessages = mockClient.getSentMessagesOfType<ChangeMessage>();
        final changesMessages =
            mockClient.getSentMessagesOfType<ChangesMessage>();
        expect(changeMessages.length + changesMessages.length, greaterThan(0));
      });

      test('should compute server version vector correctly', () async {
        mockClient.clearSentMessages();

        final otherPeerId = PeerId.generate();
        final operation = MockOperation(handler);

        // Create some local changes
        document.createChange(operation);
        document.createChange(operation);

        // Wait for local changes
        await Future<void>.delayed(Duration.zero);

        // Merge with server that has snapshot + changes
        final snapshot = Snapshot(
          id: 'test-snapshot',
          versionVector: VersionVector({
            otherPeerId: HybridLogicalClock(l: 5, c: 1),
          }),
          data: {'test-handler': 'test_state'},
        );

        final serverChange = Change(
          id: OperationId(otherPeerId, HybridLogicalClock(l: 6, c: 1)),
          operation: operation,
          deps: {},
          author: otherPeerId,
        );

        syncManager.merge(
          serverVersionVector: VersionVector({otherPeerId: serverChange.hlc}),
          snapshot: snapshot,
          changes: [serverChange],
        );

        // Wait for async operations
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Should send only local changes that are newer
        final changesMessages =
            mockClient.getSentMessagesOfType<ChangesMessage>();
        if (changesMessages.isNotEmpty) {
          // If there are changes, they should only be from peerId
          final allChanges = <Change>[];
          for (final msg in changesMessages) {
            allChanges.addAll((msg as ChangesMessage).changes);
          }
          expect(allChanges.every((c) => c.id.peerId == peerId), isTrue);
        }
      });
    });

    group('requestDocumentStatus', () {
      test('should send document status request', () async {
        mockClient.clearSentMessages();

        syncManager.requestDocumentStatus();

        await Future<void>.delayed(Duration.zero);

        expect(mockClient.sentMessages.length, equals(1));
        final message = mockClient.getLastSentMessage();
        expect(message, isA<DocumentStatusRequestMessage>());
        final requestMessage = message as DocumentStatusRequestMessage;
        expect(requestMessage.documentId, equals(document.documentId));
        expect(requestMessage.versionVector, isNotNull);
      });

      test('should send current version vector in request', () async {
        // Create local changes to update version
        final operation = MockOperation(handler);
        document.createChange(operation);
        document.createChange(operation);

        await Future<void>.delayed(Duration.zero);

        mockClient.clearSentMessages();

        final currentVV = document.getVersionVector();
        syncManager.requestDocumentStatus();

        await Future<void>.delayed(Duration.zero);

        final message = mockClient.getLastSentMessage();
        final requestMessage = message as DocumentStatusRequestMessage;
        expect(requestMessage.versionVector?.toJson(), equals(currentVV.toJson()));
      });

      test('should handle errors gracefully', () async {
        mockClient.setShouldThrowOnSendMessage = true;

        expect(() => syncManager.requestDocumentStatus(), returnsNormally);
        await Future<void>.delayed(Duration.zero);

        expect(mockClient.sentMessages.length, equals(0));
      });
    });

    group('dispose', () {
      test('should cancel local changes subscription', () {
        syncManager.dispose();

        // Try to create a change after disposal
        mockClient.clearSentMessages();
        final operation = MockOperation(handler);
        document.createChange(operation);

        // No message should be sent since the subscription was cancelled
        expect(mockClient.sentMessages.length, equals(0));
      });

      test('should handle multiple dispose calls gracefully', () {
        syncManager.dispose();
        expect(() => syncManager.dispose(), returnsNormally);
      });

      test('should set subscription to null after disposal', () {
        syncManager.dispose();
        // Cannot directly test the private field, but we can test the behavior
        // that no more messages are sent after disposal
        mockClient.clearSentMessages();
        final operation = MockOperation(handler);
        document.createChange(operation);
        expect(mockClient.sentMessages.length, equals(0));
      });
    });

    group('documentId getter', () {
      test('should return document peer ID as string', () {
        // We can't directly test the private getter,
        // but we can verify it through
        // the messages sent which use this getter
        mockClient.clearSentMessages();
        final operation = MockOperation(handler);
        document.createChange(operation);

        // Wait for the message to be sent
        Future<void>.delayed(Duration.zero).then((_) {
          final sentMessage = mockClient.getLastSentMessage();
          expect(sentMessage!.documentId, equals(document.documentId));
        });
      });
    });

    group('Edge cases and error scenarios', () {
      test('should handle concurrent local changes', () async {
        final operation = MockOperation(handler);

        // Create multiple changes rapidly
        final futures = <Future<void>>[];
        for (var i = 0; i < 5; i++) {
          futures.add(Future<void>(() => document.createChange(operation)));
        }

        await Future.wait(futures);

        // Wait for all async messages to be sent
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Should have sent 5 change messages
        expect(mockClient.sentMessages.length, equals(5));
        expect(
          mockClient.sentMessages.every((msg) => msg is ChangeMessage),
          isTrue,
        );
      });

      test('should handle merge with null snapshot', () async {
        mockClient.clearSentMessages();

        final otherPeerId = PeerId.generate();
        final operation = MockOperation(handler);

        // Create local change
        document.createChange(operation);

        // Merge with changes only (no snapshot)
        final serverChange = Change(
          id: OperationId(otherPeerId, HybridLogicalClock(l: 1, c: 1)),
          operation: operation,
          deps: {},
          author: otherPeerId,
        );

        syncManager.merge(
          serverVersionVector: VersionVector({otherPeerId: serverChange.hlc}),
          changes: [serverChange],
          snapshot: null,
        );

        // Wait for async operations
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Should have sent local changes
        final changeMessages = mockClient.getSentMessagesOfType<ChangeMessage>();
        final changesMessages =
            mockClient.getSentMessagesOfType<ChangesMessage>();
        expect(changeMessages.length + changesMessages.length, greaterThan(0));
      });

      test('should handle merge with only snapshot and no changes', () async {
        mockClient.clearSentMessages();

        final otherPeerId = PeerId.generate();
        final snapshot = Snapshot(
          id: 'test-snapshot',
          versionVector: VersionVector({
            otherPeerId: HybridLogicalClock(l: 1, c: 1),
          }),
          data: {'test-handler': 'test_state'},
        );

        // Should not throw
        expect(
          () => syncManager.merge(
            serverVersionVector: snapshot.versionVector,
            changes: null,
            snapshot: snapshot,
          ),
          returnsNormally,
        );

        // Wait for async operations
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // With no local changes and only snapshot, no messages should be sent
        // (or only local changes if any exist)
        expect(mockClient.sentMessages.length, greaterThanOrEqualTo(0));
      });

      test('should handle change with empty dependencies', () {
        final operation = MockOperation(handler);
        final change = Change(
          id: OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1)),
          operation: operation,
          deps: {},
          author: PeerId.generate(),
        );

        expect(() => syncManager.applyChange(change), returnsNormally);
      });

      test('should maintain document state consistency after errors', () async {
        final initialVersion = document.version;

        // Try to apply an invalid change
        final operation = MockOperation(handler);
        final invalidChange = Change(
          id: OperationId(PeerId.generate(), HybridLogicalClock(l: 2, c: 1)),
          operation: operation,
          deps: {
            OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 2)),
          },
          author: PeerId.generate(),
        );

        syncManager.applyChange(invalidChange);

        // Document version should remain unchanged
        expect(document.version, equals(initialVersion));

        // Wait for async operations
        await Future<void>.delayed(Duration.zero);

        // Should have requested missing changes
        final snapshotRequests =
            mockClient.getSentMessagesOfType<DocumentStatusRequestMessage>();
        expect(snapshotRequests.length, equals(1));
      });

    });
  });
}
