import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

class TestHandler extends Handler {
  TestHandler(CRDTDocument doc) : super(doc);

  @override
  String get id => 'test-handler';

  @override
  String getState() {
    return '';
  }
}

void main() {
  group('OperationType', () {
    late Handler handler;
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
      final handler1 = TestHandler(doc);
      final handler2 = TestHandler(doc);
      final operationType1 = OperationType.insert(handler1);
      final operationType2 = OperationType.insert(handler2);
      expect(operationType1, equals(operationType2));
    });

    test('hashCode is consistent with equality', () {
      final operationType1 = OperationType.insert(handler);
      final operationType2 = OperationType.insert(handler);
      final operationType3 = OperationType.delete(handler);
      final handler2 = TestHandler(doc);
      final operationType4 = OperationType.insert(handler2);

      expect(operationType1.hashCode, equals(operationType2.hashCode));
      expect(operationType1.hashCode, isNot(equals(operationType3.hashCode)));
      expect(operationType1.hashCode, equals(operationType4.hashCode));
    });

    test('toPayload returns correct string format', () {
      final operationType = OperationType.insert(handler);
      expect(operationType.toPayload(), equals('TestHandler:insert'));
    });

    test('fromPayload creates correct operation type', () {
      final payload = 'TestHandler:insert';
      final operationType = OperationType.fromPayload(payload);
      expect(operationType.handler, equals('TestHandler'));
      expect(operationType.type, equals('insert'));
    });

    test('fromPayload creates correct operation type for delete', () {
      final payload = 'TestHandler:delete';
      final operationType = OperationType.fromPayload(payload);
      expect(operationType.handler, equals('TestHandler'));
      expect(operationType.type, equals('delete'));
    });

    test('fromPayload with invalid format throws FormatException', () {
      final payload = 'invalid-format';
      expect(
        () => OperationType.fromPayload(payload),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromPayload with missing handler throws FormatException', () {
      final payload = ':insert';
      expect(
        () => OperationType.fromPayload(payload),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromPayload with missing type throws FormatException', () {
      final payload = 'TestHandler:';
      expect(
        () => OperationType.fromPayload(payload),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromPayload with multiple colons throws FormatException', () {
      final payload = 'TestHandler:insert:extra';
      expect(
        () => OperationType.fromPayload(payload),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
