import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('CrdtException', () {
    test('toString returns correct format', () {
      const message = 'Test message';
      const exception = CrdtException(message);
      expect(exception.toString(), equals('CrdtException: $message'));
    });
  });

  group('UnknownOperationKindException', () {
    test('keeps the envelope fields and names all three in the message', () {
      const exception = UnknownOperationKindException(
        handlerType: 'CRDTFugueTextHandler',
        handlerId: 'text-1',
        kind: 99,
      );

      expect(exception.handlerType, equals('CRDTFugueTextHandler'));
      expect(exception.handlerId, equals('text-1'));
      expect(exception.kind, equals(99));
      expect(
        exception.toString(),
        allOf(
          contains('CRDTFugueTextHandler'),
          contains('text-1'),
          contains('99'),
        ),
      );
    });
  });
}
