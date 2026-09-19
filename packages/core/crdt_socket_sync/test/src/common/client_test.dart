import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:test/test.dart';

import '../utils/mock_handler.dart';
import '../utils/mock_socket_client.dart';

MockCRDTSocketClient _client({
  DocumentCapabilities? capabilities,
  CRDTDocument? document,
}) {
  final doc = document ?? CRDTDocument();
  return MockCRDTSocketClient(
    document: doc,
    author: doc.peerId,
    capabilities: capabilities,
  );
}

void main() {
  group('CRDTSocketClient.capabilities', () {
    test('reads the document when nothing is declared', () {
      final document = CRDTDocument();
      MockHandler(document);

      expect(
        _client(document: document).capabilities.handlerTypes,
        contains('MockHandler'),
      );
    });

    test('a build with nothing set up claims nothing', () {
      // The footgun this parameter exists for: a document reports what it has
      // been set up for, and an app usually opens its handlers after connect().
      // That is why a derived description travels as incomplete.
      expect(_client().capabilities.handlerTypes, isEmpty);
    });

    test('the declaration wins, whatever the document has open', () {
      // Stating the build once, at construction, is what stops the answer from
      // depending on when the app happens to open a handler.
      final declared = DocumentCapabilities({
        'MockHandler': const HandlerFormats(
          operationKinds: {0},
          blobVersions: BlobVersionRange.single(1),
        ),
      });

      expect(_client(capabilities: declared).capabilities, declared);
    });
  });

  group('CRDTSocketClient.refuseBuild', () {
    test('latches the reason and moves to the terminal status', () async {
      final client = _client();
      final seen = <ConnectionStatus>[];
      client.connectionStatus.listen(seen.add);

      client.refuse(
        code: Protocol.errorUnsupportedClient,
        reason: 'nope',
      );
      await Future<void>.delayed(Duration.zero);

      expect(client.isUnsupported, isTrue);
      expect(client.incompatibility?.code, Protocol.errorUnsupportedClient);
      expect(client.incompatibility?.isMissingOperationKinds, isTrue);
      expect(seen, contains(ConnectionStatus.unsupported));
    });

    test('keeps the first reason, and the status stays terminal', () async {
      final client = _client()
        ..refuse(
          code: Protocol.errorUnsupportedProtocolVersion,
          reason: 'first',
        )
        ..refuse(code: Protocol.errorUnsupportedClient, reason: 'second');

      expect(client.incompatibility?.message, 'first');

      // A refusal is terminal: the teardown that follows it must not report
      // the client as merely disconnected.
      client.setConnectionStatus(ConnectionStatus.disconnected);
      expect(client.connectionStatusValue, ConnectionStatus.unsupported);
    });
  });

  group('CRDTSocketClient.refuseServerProtocolMismatch', () {
    test('refuses a server that speaks another version', () {
      final client = _client();

      expect(
        client.refuseProtocolMismatch(Protocol.protocolVersion + 1),
        isTrue,
      );
      expect(client.incompatibility?.isProtocolVersionMismatch, isTrue);
    });

    test('lets a matching server through', () {
      final client = _client();

      expect(
        client.refuseProtocolMismatch(Protocol.protocolVersion),
        isFalse,
      );
      expect(client.isUnsupported, isFalse);
    });
  });

  group('CRDTSocketClient.lastFault', () {
    SyncFault fault(String reason) =>
        SyncFault(reason: reason, error: StateError(reason));

    test('is null until something fails', () {
      expect(_client().lastFault, isNull);
    });

    test('holds the fault for a listener that subscribed too late', () {
      final client = _client()..reportSyncFault(fault('first'));

      expect(client.lastFault?.reason, 'first');
    });

    test('keeps the latest one, and is never cleared', () {
      final client = _client()
        ..reportSyncFault(fault('first'))
        ..reportSyncFault(fault('second'));

      expect(client.lastFault?.reason, 'second');
    });
  });
}
