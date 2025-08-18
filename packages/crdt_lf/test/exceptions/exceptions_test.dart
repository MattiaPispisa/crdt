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
}
