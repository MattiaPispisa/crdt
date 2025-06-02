import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/client.dart';
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
          hlc: HybridLogicalClock(l: 1, c: 1),
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
          hlc: HybridLogicalClock(l: 2, c: 1),
          author: PeerId.generate(),
        );

        // This should trigger the error handling path
        syncManager.applyChange(nonReadyChange);

        // Wait for the async snapshot request to be sent
        await Future<void>.delayed(Duration.zero);

        // Should have sent a snapshot request
        expect(mockClient.sentMessages.length, equals(1));
        final sentMessage = mockClient.getLastSentMessage();
        expect(sentMessage, isA<SnapshotRequestMessage>());
        expect(sentMessage!.documentId, equals(document.peerId.toString()));
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
          hlc: HybridLogicalClock(l: 2, c: 1),
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
            hlc: HybridLogicalClock(l: 1, c: 1),
            author: PeerId.generate(),
          ),
          Change(
            id: OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 2)),
            operation: operation,
            deps: {},
            hlc: HybridLogicalClock(l: 1, c: 2),
            author: PeerId.generate(),
          ),
        ];

        expect(() => syncManager.applyChanges(changes), returnsNormally);
      });

      test('should apply empty list of changes without error', () {
        expect(() => syncManager.applyChanges([]), returnsNormally);
      });

      test('should handle mixed valid and invalid changes', () async {
        mockClient.clearSentMessages();

        final operation = MockOperation(handler);
        final validChange = Change(
          id: OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1)),
          operation: operation,
          deps: {},
          hlc: HybridLogicalClock(l: 1, c: 1),
          author: PeerId.generate(),
        );

        final invalidChange = Change(
          id: OperationId(PeerId.generate(), HybridLogicalClock(l: 2, c: 1)),
          operation: operation,
          deps: {
            OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 2)),
          },
          hlc: HybridLogicalClock(l: 2, c: 1),
          author: PeerId.generate(),
        );

        syncManager.applyChanges([validChange, invalidChange]);

        // Wait for async operations
        await Future<void>.delayed(Duration.zero);

        // Should have sent at least one snapshot request
        // due to the invalid change
        final snapshotRequests =
            mockClient.getSentMessagesOfType<SnapshotRequestMessage>();
        expect(snapshotRequests.length, greaterThan(0));
      });
    });

    group('applySnapshot', () {
      test('should apply snapshot successfully', () {
        final snapshot = Snapshot(
          id: 'test-snapshot',
          versionVector:
              VersionVector({peerId: HybridLogicalClock(l: 1, c: 1)}),
          data: {'test-handler': 'test_state'},
        );

        final result = syncManager.applySnapshot(snapshot);
        expect(result, isTrue);
      });

      test('should return false for outdated snapshot', () {
        // First create some local changes to advance the document version
        final operation = MockOperation(handler);
        document.createChange(operation);

        // Try to apply an older snapshot
        final outdatedSnapshot = Snapshot(
          id: 'test-snapshot',
          versionVector: VersionVector({}), // Empty version vector (older)
          data: {'test-handler': 'test_state'},
        );

        final result = syncManager.applySnapshot(outdatedSnapshot);
        expect(result, isFalse);
      });

      test('should apply newer snapshot over existing state', () {
        final snapshot = Snapshot(
          id: 'test-snapshot',
          versionVector:
              VersionVector({peerId: HybridLogicalClock(l: 5, c: 1)}),
          data: {'test-handler': 'test_state'},
        );

        final result = syncManager.applySnapshot(snapshot);
        expect(result, isTrue);
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

    group('_documentId getter', () {
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
          expect(sentMessage!.documentId, equals(document.peerId.toString()));
        });
      });
    });

    group('Edge cases and error scenarios', () {
      test('should handle document with no changes gracefully', () {
        expect(() => syncManager.applyChanges([]), returnsNormally);

        final snapshot = Snapshot(
          id: 'test-snapshot',
          versionVector: VersionVector({}),
          data: {'test-handler': 'test_state'},
        );

        expect(syncManager.applySnapshot(snapshot), isTrue);
      });

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

      test('should handle snapshot with empty data', () {
        final snapshot = Snapshot(
          id: 'empty-snapshot',
          versionVector:
              VersionVector({peerId: HybridLogicalClock(l: 1, c: 1)}),
          data: {},
        );

        expect(syncManager.applySnapshot(snapshot), isTrue);
      });

      test('should handle change with empty dependencies', () {
        final operation = MockOperation(handler);
        final change = Change(
          id: OperationId(PeerId.generate(), HybridLogicalClock(l: 1, c: 1)),
          operation: operation,
          deps: {},
          hlc: HybridLogicalClock(l: 1, c: 1),
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
          hlc: HybridLogicalClock(l: 2, c: 1),
          author: PeerId.generate(),
        );

        syncManager.applyChange(invalidChange);

        // Document version should remain unchanged
        expect(document.version, equals(initialVersion));

        // Wait for async operations
        await Future<void>.delayed(Duration.zero);

        // Should have requested missing changes
        final snapshotRequests =
            mockClient.getSentMessagesOfType<SnapshotRequestMessage>();
        expect(snapshotRequests.length, equals(1));
      });
    });
  });
}
