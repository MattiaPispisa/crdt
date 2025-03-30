import 'package:test/test.dart';
import 'package:crdt_lf/crdt_lf.dart';

void main() {
  group('CRDTTextHandler', () {
    late CRDTDocument doc;
    late CRDTTextHandler text;

    setUp(() {
      doc = CRDTDocument();
      text = CRDTTextHandler(doc, 'test-text');
    });

    test('constructor creates text handler with correct id', () {
      expect(text.id, equals('test-text'));
    });

    test('insert adds text at specified index', () {
      text.insert(0, 'Hello');
      expect(text.value, equals('Hello'));
    });

    test('insert at end adds text at the end', () {
      text.insert(0, 'Hello');
      text.insert(5, ' World');
      expect(text.value, equals('Hello World'));
    });

    test('insert at middle adds text in the middle', () {
      text.insert(0, 'Hello');
      text.insert(5, ' World');
      text.insert(6, 'Beautiful ');
      expect(text.value, equals('Hello Beautiful World'));
    });

    test('insert at out of bounds index adds text at the end', () {
      text.insert(0, 'Hello');
      text.insert(10, ' World');
      expect(text.value, equals('Hello World'));
    });

    test('delete removes text at specified index', () {
      text.insert(0, 'Hello World');
      text.delete(5, 1);
      expect(text.value, equals('HelloWorld'));
    });

    test('delete multiple characters removes specified count', () {
      text.insert(0, 'Hello World');
      text.delete(5, 2);
      expect(text.value, equals('Helloorld'));
    });

    test('delete at end removes until the end', () {
      text.insert(0, 'Hello World');
      text.delete(5, 10);
      expect(text.value, equals('Hello'));
    });

    test('delete at out of bounds index does nothing', () {
      text.insert(0, 'Hello World');
      text.delete(20, 5);
      expect(text.value, equals('Hello World'));
    });

    test('length returns correct text length', () {
      text.insert(0, 'Hello World');
      expect(text.length, equals(11));
    });

    test('value caches result until invalidated', () {
      text.insert(0, 'Hello');
      final value1 = text.value;
      final value2 = text.value;
      expect(identical(value1, value2), isTrue);
    });

    test('value recomputes after cache invalidation', () {
      text.insert(0, 'Hello');
      final value1 = text.value;
      text.insert(5, ' World');
      final value2 = text.value;
      expect(identical(value1, value2), isFalse);
      expect(value2, equals('Hello World'));
    });

    test('toString returns correct string representation', () {
      text.insert(0, 'Hello World');
      expect(text.toString(), equals('CRDTText(test-text, "Hello World")'));
    });

    test('toString truncates long text', () {
      text.insert(0, 'This is a very long text that should be truncated');
      expect(
        text.toString(),
        equals('CRDTText(test-text, "This is a very long ...")'),
      );
    });

    test('multiple operations maintain correct order', () {
      text.insert(0, 'Hello'); // Hello
      text.insert(5, ' World'); // Hello World
      text.delete(5, 1); // HelloWorld
      text.insert(5, ' Beautiful '); // Hello Beautiful World
      text.delete(0, 6); // Beautiful World
      expect(text.value, equals('Beautiful World'));
    });

    test('operations from different peers merge correctly', () {
      final doc1 = CRDTDocument();
      final doc2 = CRDTDocument();
      final text1 = CRDTTextHandler(doc1, 'test-text');
      final text2 = CRDTTextHandler(doc2, 'test-text');

      text1.insert(0, 'Hello');
      text2.insert(0, 'World');

      // Merge changes
      doc2.import(doc1.export());
      doc1.import(doc2.export());

      // Both documents should have the same state
      expect(text1.value, equals(text2.value));
      expect(text1.value, contains('Hello'));
      expect(text1.value, contains('World'));
      expect(
        text1.value == "HelloWorld" || text1.value == "WorldHello",
        isTrue,
      );
    });
  });
}
