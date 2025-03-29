import 'package:crdt_lf/src/operation/type.dart';
import 'package:crdt_lf/src/handler/handler.dart';
import 'package:test/test.dart';

class TestHandler implements Handler {
  @override
  String get id => 'test-handler';
}

void main() {
  group('OperationType', () {
    late Handler handler;

    setUp(() {
      handler = TestHandler();
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
      final handler1 = TestHandler();
      final handler2 = TestHandler();
      final operationType1 = OperationType.insert(handler1);
      final operationType2 = OperationType.insert(handler2);
      expect(operationType1, equals(operationType2));
    });

    test('hashCode is consistent with equality', () {
      final operationType1 = OperationType.insert(handler);
      final operationType2 = OperationType.insert(handler);
      final operationType3 = OperationType.delete(handler);
      final handler2 = TestHandler();
      final operationType4 = OperationType.insert(handler2);

      expect(operationType1.hashCode, equals(operationType2.hashCode));
      expect(operationType1.hashCode, isNot(equals(operationType3.hashCode)));
      expect(operationType1.hashCode, equals(operationType4.hashCode));
    });
  });
}
