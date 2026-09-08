import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:test/test.dart';

import '../utils/mock_handler.dart';

void main() {
  group('SyncCapabilities', () {
    test('reads the decodable kinds of every registered handler', () {
      final document = CRDTDocument();
      MockHandler(document);

      final capabilities = SyncCapabilities.of(document);

      expect(
        capabilities.operationKinds,
        {
          'MockHandler': {OperationType.kindInsert},
        },
      );
    });

    test('keys on handlerType, so two peers agree after minification', () {
      final document = CRDTDocument();
      NewerMockHandler(document);

      // The class is NewerMockHandler, the declared type tag is MockHandler.
      expect(
        SyncCapabilities.of(document).operationKinds.keys,
        ['MockHandler'],
      );
    });

    test('json round-trips, with kinds in a stable order', () {
      final capabilities = SyncCapabilities({
        'MockHandler': {2, 0, 1},
      });

      expect(capabilities.toJson(), {
        'MockHandler': [0, 1, 2],
      });
      final json =
          jsonDecode(jsonEncode(capabilities.toJson())) as Map<String, dynamic>;
      expect(
        SyncCapabilities.fromJson(json).operationKinds,
        capabilities.operationKinds,
      );
    });

    group('missingFrom', () {
      test('names the kind the other peer has and this one lacks', () {
        final older = CRDTDocument();
        MockHandler(older);
        final newer = CRDTDocument();
        NewerMockHandler(newer);

        final missing =
            SyncCapabilities.of(older).missingFrom(SyncCapabilities.of(newer));

        expect(missing, [
          const MissingOperationKind(
            handlerType: 'MockHandler',
            kind: OperationType.kindDelete,
          ),
        ]);
      });

      test('is empty when this peer is the newer one', () {
        final older = CRDTDocument();
        MockHandler(older);
        final newer = CRDTDocument();
        NewerMockHandler(newer);

        expect(
          SyncCapabilities.of(newer).missingFrom(SyncCapabilities.of(older)),
          isEmpty,
        );
      });

      test('ignores a handler type this peer has not opened', () {
        // Not a fault: a peer legitimately syncs a document whose handlers it
        // never opens, and lazy registration means it may not have opened them
        // yet.
        final client = SyncCapabilities({
          'MockHandler': {0},
        });
        final server = SyncCapabilities({
          'MockHandler': {0},
          'CRDTFugueTextHandler': {0, 1, 2},
        });

        expect(client.missingFrom(server), isEmpty);
      });
    });
  });
}
