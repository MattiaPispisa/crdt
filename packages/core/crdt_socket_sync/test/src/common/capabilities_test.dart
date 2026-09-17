import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:test/test.dart';

import '../utils/mock_handler.dart';

/// What a peer says it can read.
SyncCapabilities _reads(Map<String, HandlerFormats> byType) =>
    SyncCapabilities(DocumentCapabilities(byType));

/// What a document's data asks for.
DocumentRequirements _holds(Map<String, HandlerFormats> byType) =>
    DocumentRequirements(byType);

void main() {
  group('SyncCapabilities', () {
    test('carries what a build declares, keyed by handler type', () {
      final document = CRDTDocument();
      NewerMockHandler(document);

      // The class is NewerMockHandler, the declared type tag is MockHandler:
      // the tag is what travels, so it is what both peers key on.
      final capabilities =
          SyncCapabilities(document.describeBuildCapabilities());

      expect(capabilities.capabilities.handlerTypes, contains('MockHandler'));
      expect(
        capabilities.capabilities.handlerTypes,
        isNot(contains('NewerMockHandler')),
      );
    });

    test('json round-trips, with kinds in a stable order', () {
      final capabilities = _reads({
        'MockHandler': const HandlerFormats(
          operationKinds: {2, 0, 1},
          blobVersions: BlobVersionRange.single(1),
        ),
      });

      expect(capabilities.toJson(), {
        'MockHandler': {
          'kinds': [0, 1, 2],
          'blob': {'min': 1, 'max': 1},
        },
      });
      final json =
          jsonDecode(jsonEncode(capabilities.toJson())) as Map<String, dynamic>;
      expect(
        SyncCapabilities.fromJson(json).capabilities,
        capabilities.capabilities,
      );
    });

    test('leaves out a blob version it does not know', () {
      // A type read back from change envelopes alone: an envelope says nothing
      // about snapshots, and silence is not a claim.
      final capabilities = _reads({
        'MockHandler': const HandlerFormats(operationKinds: {0}),
      });

      expect(capabilities.toJson(), {
        'MockHandler': {
          'kinds': [0],
        },
      });
      expect(
        SyncCapabilities.fromJson(capabilities.toJson())
            .capabilities['MockHandler']
            ?.blobVersions,
        isNull,
      );
    });

    group('missingFrom', () {
      test('names the kind the other side holds and this one cannot read', () {
        final older = _reads({
          'MockHandler': const HandlerFormats(
            operationKinds: {OperationType.kindInsert},
          ),
        });
        final data = _holds({
          'MockHandler': const HandlerFormats(
            operationKinds: {
              OperationType.kindInsert,
              OperationType.kindDelete,
            },
          ),
        });

        expect(older.missingFrom(data), [
          const MissingOperationKind(
            handlerType: 'MockHandler',
            kind: OperationType.kindDelete,
          ),
        ]);
      });

      test('is empty when this build reads more than the other side holds', () {
        final newer = _reads({
          'MockHandler': const HandlerFormats(
            operationKinds: {
              OperationType.kindInsert,
              OperationType.kindDelete,
            },
          ),
        });
        final data = _holds({
          'MockHandler': const HandlerFormats(
            operationKinds: {OperationType.kindInsert},
          ),
        });

        expect(newer.missingFrom(data), isEmpty);
      });

      test('silence about a type is a refusal only when the claim is complete',
          () {
        final data = _holds({
          'MockHandler': const HandlerFormats(operationKinds: {0}),
          'CRDTFugueTextHandler':
              const HandlerFormats(operationKinds: {0, 1, 2}),
        });
        final names = {
          'MockHandler': const HandlerFormats(operationKinds: {0}),
        };

        // Derived from a document: it knows the handlers opened so far, and an
        // app usually opens one after connecting. Silence says nothing.
        expect(
          SyncCapabilities(DocumentCapabilities(names)).missingFrom(data),
          isEmpty,
        );

        // Written out by hand: it names every type this build reads, so a type
        // left out really is one it cannot read. Reported once for the type,
        // because what is missing is the handler, not three kinds.
        expect(
          SyncCapabilities(DocumentCapabilities(names), complete: true)
              .missingFrom(data),
          [const UnknownHandlerType(handlerType: 'CRDTFugueTextHandler')],
        );
      });

      test('a complete claim catches a type known only by its blob version',
          () {
        // The data knows the type from a snapshot alone, so it has no kinds to
        // report as missing. Without naming the handler itself, nothing would
        // be reported and the client would pass.
        final data = _holds({
          'MockHandler': const HandlerFormats(operationKinds: {0}),
          'OnlySnapshotted': const HandlerFormats(
            operationKinds: {},
            blobVersions: BlobVersionRange.single(2),
          ),
        });
        final claim = SyncCapabilities(
          DocumentCapabilities({
            'MockHandler': const HandlerFormats(operationKinds: {0}),
          }),
          complete: true,
        );

        expect(claim.missingFrom(data), [
          const UnknownHandlerType(handlerType: 'OnlySnapshotted'),
        ]);
      });

      test('a type it does name is checked in full, complete or not', () {
        // The incomplete case is not a free pass: what the peer *did* say is
        // taken at its word.
        final data = _holds({
          'MockHandler': const HandlerFormats(operationKinds: {0, 1}),
        });
        final partial = _reads({
          'MockHandler': const HandlerFormats(operationKinds: {0}),
        });

        expect(partial.missingFrom(data), [
          const MissingOperationKind(handlerType: 'MockHandler', kind: 1),
        ]);
      });

      test('refuses a build against data holding a version it cannot read', () {
        // A document that merged snapshots from two peers on different builds
        // holds a range covering both, and a build that stops at v1 cannot
        // read the top of it.
        final readsV1 = _reads({
          'MockHandler': const HandlerFormats(
            operationKinds: {0},
            blobVersions: BlobVersionRange.single(1),
          ),
        });
        final holdsBoth = _holds({
          'MockHandler': const HandlerFormats(
            operationKinds: {0},
            blobVersions: BlobVersionRange(1, 2),
          ),
        });

        expect(readsV1.missingFrom(holdsBoth), [
          const SnapshotBlobTooNew(
            handlerType: 'MockHandler',
            reads: BlobVersionRange.single(1),
            holds: 2,
          ),
        ]);
      });

      test('a blob version only one side knows is not a disagreement', () {
        final client = _reads({
          'MockHandler': const HandlerFormats(
            operationKinds: {0},
            blobVersions: BlobVersionRange.single(1),
          ),
        });
        final data = _holds({
          'MockHandler': const HandlerFormats(operationKinds: {0}),
        });

        expect(client.missingFrom(data), isEmpty);
      });

      test('is empty against data that holds nothing', () {
        expect(_reads({}).missingFrom(_holds({})), isEmpty);
      });
    });
  });
}
