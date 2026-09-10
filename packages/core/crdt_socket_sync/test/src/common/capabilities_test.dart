import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:test/test.dart';

import '../utils/mock_handler.dart';

void main() {
  group('SyncCapabilities', () {
    test('carries what a build declares, keyed by handler type', () {
      final document = CRDTDocument();
      NewerMockHandler(document);

      // The class is NewerMockHandler, the declared type tag is MockHandler:
      // the tag is what travels, so it is what both peers key on.
      final capabilities =
          SyncCapabilities(document.describeBuildCapabilities());

      expect(capabilities.operationKinds.keys, ['MockHandler']);
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
      test('names the kind the other side holds and this one cannot read', () {
        final older = SyncCapabilities({
          'MockHandler': {OperationType.kindInsert},
        });
        final data = SyncCapabilities({
          'MockHandler': {OperationType.kindInsert, OperationType.kindDelete},
        });

        expect(older.missingFrom(data), [
          const MissingOperationKind(
            handlerType: 'MockHandler',
            kind: OperationType.kindDelete,
          ),
        ]);
      });

      test('is empty when this build reads more than the other side holds', () {
        final newer = SyncCapabilities({
          'MockHandler': {OperationType.kindInsert, OperationType.kindDelete},
        });
        final data = SyncCapabilities({
          'MockHandler': {OperationType.kindInsert},
        });

        expect(newer.missingFrom(data), isEmpty);
      });

      test('a type this build says nothing about counts as unreadable', () {
        // These describe a build, not a moment: silence about a type means the
        // build cannot read it. Passing it over is what used to let a client
        // through on data it had no way of reading.
        final client = SyncCapabilities({
          'MockHandler': {0},
        });
        final data = SyncCapabilities({
          'MockHandler': {0},
          'CRDTFugueTextHandler': {0, 1, 2},
        });

        expect(
          client.missingFrom(data),
          [
            const MissingOperationKind(
              handlerType: 'CRDTFugueTextHandler',
              kind: 0,
            ),
            const MissingOperationKind(
              handlerType: 'CRDTFugueTextHandler',
              kind: 1,
            ),
            const MissingOperationKind(
              handlerType: 'CRDTFugueTextHandler',
              kind: 2,
            ),
          ],
        );
      });

      test('is empty against data that holds nothing', () {
        expect(SyncCapabilities({}).missingFrom(SyncCapabilities({})), isEmpty);
      });
    });
  });
}
