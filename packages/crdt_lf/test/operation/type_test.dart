import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';

void main() {
  group('OperationType', () {
    late Handler<dynamic> handler;
    late CRDTDocument doc;
    late PeerId author;

    setUp(() {
      author = PeerId.generate();
      doc = CRDTDocument(peerId: author);
      handler = TestHandler(doc);
    });

    test('insert factory creates correct operation type', () {
      final operationType = OperationType.insert(handler);
      expect(operationType.type, equals('insert'));
      expect(operationType.handler, equals('TestHandler'));
    });

    test('delete factory creates correct operation type', () {
      final operationType = OperationType.delete(handler);
      expect(operationType.type, equals('delete'));
      expect(operationType.handler, equals('TestHandler'));
    });

    test('same operation types with same handler are equal', () {
      final operationType1 = OperationType.insert(handler);
      final operationType2 = OperationType.insert(handler);
      expect(operationType1, equals(operationType2));
    });

    test('different operation types are not equal', () {
      final insertType = OperationType.insert(handler);
      final deleteType = OperationType.delete(handler);
      expect(insertType, isNot(equals(deleteType)));
    });

    test('same operation types with different handlers are not equal', () {
      final handler1 = TestHandler(doc, id: 'test-handler-1');
      final handler2 = TestHandler(doc, id: 'test-handler-2');
      final operationType1 = OperationType.insert(handler1);
      final operationType2 = OperationType.insert(handler2);
      expect(operationType1, equals(operationType2));
    });

    test('hashCode is consistent with equality', () {
      final operationType1 = OperationType.insert(handler);
      final operationType2 = OperationType.insert(handler);
      final operationType3 = OperationType.delete(handler);
      final handler2 = TestHandler(doc, id: 'test-handler-2');
      final operationType4 = OperationType.insert(handler2);

      expect(operationType1.hashCode, equals(operationType2.hashCode));
      expect(operationType1.hashCode, isNot(equals(operationType3.hashCode)));
      expect(operationType1.hashCode, equals(operationType4.hashCode));
    });

    test('toPayload returns correct string format', () {
      final operationType = OperationType.insert(handler);
      expect(operationType.toPayload(), equals('TestHandler:insert'));
    });

    test('the four conventional factories carry their kind', () {
      expect(
        OperationType.insert(handler).kind,
        equals(OperationType.kindInsert),
      );
      expect(
        OperationType.delete(handler).kind,
        equals(OperationType.kindDelete),
      );
      expect(
        OperationType.update(handler).kind,
        equals(OperationType.kindUpdate),
      );
      expect(
        OperationType.move(handler).kind,
        equals(OperationType.kindMove),
      );
    });

    group('custom', () {
      test('declares a kind and a name of its own', () {
        final increment = OperationType.custom(
          handler,
          kind: 7,
          name: 'increment',
        );

        expect(increment.kind, equals(7));
        expect(increment.type, equals('increment'));
        expect(increment.handler, equals('TestHandler'));
        expect(increment.toPayload(), equals('TestHandler:increment'));
      });

      test('two kinds with the same name are not equal', () {
        final a = OperationType.custom(handler, kind: 4, name: 'tick');
        final b = OperationType.custom(handler, kind: 5, name: 'tick');

        expect(a, isNot(equals(b)));
        expect(a.hashCode, isNot(equals(b.hashCode)));
      });

      test('may reuse a conventional kind under another name', () {
        final aliased = OperationType.custom(
          handler,
          kind: OperationType.kindInsert,
          name: 'append',
        );

        expect(aliased.kind, equals(OperationType.kindInsert));
        expect(aliased, isNot(equals(OperationType.insert(handler))));
      });

      test('rejects a kind that would collide with the stamp flag', () {
        expect(
          () => OperationType.custom(handler, kind: 128, name: 'nope'),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => OperationType.custom(handler, kind: 255, name: 'nope'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects a negative kind', () {
        expect(
          () => OperationType.custom(handler, kind: -1, name: 'nope'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('accepts the boundary value', () {
        expect(
          OperationType.custom(
            handler,
            kind: OperationType.maxKind,
            name: 'edge',
          ).kind,
          equals(127),
        );
      });
    });
  });
}
