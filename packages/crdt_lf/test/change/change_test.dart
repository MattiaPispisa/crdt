import 'dart:typed_data';

import 'package:crdt_lf/src/change/change.dart';
import 'package:crdt_lf/src/document.dart';
import 'package:crdt_lf/src/handler/handler.dart';
import 'package:crdt_lf/src/operation/id.dart';
import 'package:crdt_lf/src/operation/operation.dart';
import 'package:crdt_lf/src/peer_id.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';

void main() {
  group('Change', () {
    late OperationId id;
    late Set<OperationId> deps;
    late HybridLogicalClock hlc;
    late PeerId author;
    late Operation operation;
    late Handler<dynamic> handler;

    setUp(() {
      final doc = CRDTDocument();
      handler = TestHandler(doc);
      deps = {OperationId.parse('3a5cd393-813c-46c8-97f3-9e99a6f2c8be@1.1')};
      hlc = HybridLogicalClock(l: 1, c: 2);
      author = PeerId.generate();
      operation = TestOperation.fromHandler(handler);
      id = OperationId(author, hlc);
    });

    test('creates a new change with valid parameters', () {
      final change = Change(
        id: id,
        operation: operation,
        deps: deps,
        author: author,
      );

      expect(change.id, equals(id));
      expect(change.deps, equals(deps));
      expect(change.hlc, equals(hlc));
      expect(change.author, equals(author));
      expect(change.payloadBytes(), equals(operation.toBytes()));
    });

    test('round-trips via fromPayloadBytes', () {
      final change = Change(
        id: id,
        operation: operation,
        deps: deps,
        author: author,
      );

      final roundTripped = Change.fromPayloadBytes(
        id: change.id,
        deps: change.deps,
        author: change.author,
        payloadBytes: change.payloadBytes(),
      );

      expect(roundTripped.id, equals(change.id));
      expect(roundTripped.deps, equals(change.deps));
      expect(roundTripped.author, equals(change.author));
      expect(
        roundTripped.payloadBytes().length,
        equals(change.payloadBytes().length),
      );
    });

    test('compares different changes correctly', () {
      final change1 = Change(
        id: id,
        operation: operation,
        deps: deps,
        author: author,
      );

      final id2 = OperationId.parse('b7353649-1b52-43b0-9dbc-a843e3308cb0@1.3');
      final change2 = Change(
        id: id2,
        operation: operation,
        deps: deps,
        author: id2.peerId,
      );

      expect(change1, isNot(equals(change2)));
    });

    test('sorts changes by HLC correctly', () {
      final id1 = OperationId.parse('2951e709-9576-4e1d-9ec8-52e557bfa8cd@1.1');
      final change1 = Change(
        id: id1,
        operation: operation,
        deps: deps,
        author: id1.peerId,
      );

      final id2 = OperationId.parse('112e1539-c71a-4217-9100-4554f79096e4@1.2');
      final change2 = Change(
        id: id2,
        operation: operation,
        deps: deps,
        author: id2.peerId,
      );

      final changes = [change2, change1];
      final sorted = changes.sorted();

      expect(sorted[0], equals(change1));
      expect(sorted[1], equals(change2));
    });

    test('toString returns correct format', () {
      final change = Change(
        id: id,
        operation: operation,
        deps: deps,
        author: author,
      );

      final expected = 'Change(id: $id, deps: [${deps.first}], hlc: $hlc,'
          ' author: $author, payload: ${change.payloadBytes().length} bytes)';
      expect(change.toString(), equals(expected));
    });

    test('toBytes/fromBytes round-trip with no deps', () {
      final change = Change(
        id: id,
        operation: operation,
        deps: const {},
        author: author,
      );

      final decoded = Change.fromBytes(change.toBytes());
      expect(decoded.id, equals(change.id));
      expect(decoded.deps, isEmpty);
      expect(decoded.author, equals(change.author));
      expect(decoded.payloadBytes(), equals(change.payloadBytes()));
      expect(decoded, equals(change));
    });

    test('toBytes/fromBytes round-trip with multiple deps', () {
      final change = Change(
        id: id,
        operation: operation,
        deps: {
          OperationId.parse('3a5cd393-813c-46c8-97f3-9e99a6f2c8be@1.1'),
          OperationId.parse('b7353649-1b52-43b0-9dbc-a843e3308cb0@1.3'),
          OperationId.parse('112e1539-c71a-4217-9100-4554f79096e4@1.2'),
        },
        author: author,
      );

      final decoded = Change.fromBytes(change.toBytes());
      expect(decoded.id, equals(change.id));
      expect(decoded.deps, equals(change.deps));
      expect(decoded.author, equals(change.author));
      expect(decoded.payloadBytes(), equals(change.payloadBytes()));
    });

    test('fromBytes rejects an unknown schema version', () {
      final change = Change(
        id: id,
        operation: operation,
        deps: deps,
        author: author,
      );
      final bytes = change.toBytes();
      // Corrupt the schema version byte to an unsupported value.
      final corrupted = Uint8List.fromList(bytes)..[0] = 99;
      expect(
        () => Change.fromBytes(corrupted),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromPayloadBytes rejects mismatched author', () {
      final otherAuthor = PeerId.generate();
      expect(
        () => Change.fromPayloadBytes(
          id: id,
          deps: deps,
          author: otherAuthor,
          payloadBytes: operation.toBytes(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('fromBytes rejects empty buffer', () {
      expect(
        () => Change.fromBytes(Uint8List(0)),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromBytes rejects buffer with trailing bytes', () {
      final change = Change(
        id: id,
        operation: operation,
        deps: deps,
        author: author,
      );
      final corrupted = Uint8List.fromList([...change.toBytes(), 0xFF]);
      expect(
        () => Change.fromBytes(corrupted),
        throwsA(isA<FormatException>()),
      );
    });

    test('hashCode handles different dependencies correctly', () {
      final deps1 = {
        OperationId.parse('3a5cd393-813c-46c8-97f3-9e99a6f2c8be@1.1'),
      };
      final deps2 = {
        OperationId.parse('b7353649-1b52-43b0-9dbc-a843e3308cb0@1.3'),
      };

      final change1 = Change(
        id: id,
        operation: operation,
        deps: deps1,
        author: author,
      );

      final change2 = Change(
        id: id,
        operation: operation,
        deps: deps2,
        author: author,
      );

      expect(change1.hashCode, isNot(equals(change2.hashCode)));
    });
  });
}
