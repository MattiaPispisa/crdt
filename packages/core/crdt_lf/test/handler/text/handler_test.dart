import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../../helpers/matcher.dart';
import '../conformance/handler_conformance.dart';

void main() {
  // Non-BMP tokens, so every clause also walks text outside the BMP.
  runHandlerConformanceTests(
    spec: CRDTTextHandler.spec,
    read: (text) => text.value,
    edit: (text, random, token) {
      final length = text.length;
      switch (length == 0 ? 0 : random.nextInt(3)) {
        case 0:
          text.insert(random.nextInt(length + 1), '\u{1F600}$token');
        case 1:
          text.delete(random.nextInt(length), random.nextInt(3) + 1);
        case _:
          text.update(random.nextInt(length), '\u{1F389}$token');
      }
    },
  );

  group('CRDTTextHandler', () {
    late String handlerId;
    late PeerId author;
    late CRDTDocument doc;
    late CRDTTextHandler text;

    setUp(() {
      author = PeerId.generate();
      doc = CRDTDocument(peerId: author);
      handlerId = 'test-text';
      text = CRDTTextHandler(doc, handlerId);
    });

    test('constructor creates text handler with correct id', () {
      expect(text.id, equals('test-text'));
    });

    test('exposes a stable handlerType (minification-safe factory key)', () {
      expect(text.handlerType, 'CRDTTextHandler');
    });

    test('insert adds text at specified index', () {
      text.insert(0, 'Hello');
      expect(text.value, equals('Hello'));
    });

    test('insert at end adds text at the end', () {
      text
        ..insert(0, 'Hello')
        ..insert(5, ' World');
      expect(text.value, equals('Hello World'));
    });

    test('insert at middle adds text in the middle', () {
      text
        ..insert(0, 'Hello')
        ..insert(5, ' World')
        ..insert(6, 'Beautiful ');
      expect(text.value, equals('Hello Beautiful World'));
    });

    test('insert at out of bounds index adds text at the end', () {
      text
        ..insert(0, 'Hello')
        ..insert(10, ' World');
      expect(text.value, equals('Hello World'));
    });

    test('delete removes text at specified index', () {
      text
        ..insert(0, 'Hello World')
        ..delete(5, 1);
      expect(text.value, equals('HelloWorld'));
    });

    test('delete multiple characters removes specified count', () {
      text
        ..insert(0, 'Hello World')
        ..delete(5, 2);
      expect(text.value, equals('Helloorld'));
    });

    test('delete at end removes until the end', () {
      text
        ..insert(0, 'Hello World')
        ..delete(5, 10);
      expect(text.value, equals('Hello'));
    });

    test('delete at out of bounds index does nothing', () {
      text
        ..insert(0, 'Hello World')
        ..delete(20, 5);
      expect(text.value, equals('Hello World'));
    });

    test('update replaces text at specified index', () {
      text
        ..insert(0, 'Hello World')
        ..update(5, 'Beautiful');
      expect(text.value, equals('HelloBeauti'));
    });

    test('update replaces text at specified index with new text', () {
      text
        ..insert(0, 'Hello Beautiful')
        ..update(6, 'World');
      expect(text.value, equals('Hello Worldiful'));
    });

    test('change replaces entire text using Myers diff', () {
      text
        ..insert(0, 'Hello World')
        ..change('Hello Brave New World');
      expect(text.value, equals('Hello Brave New World'));
    });

    test('change handles complex text transformations', () {
      text
        ..insert(0, 'The quick brown fox jumps over the lazy dog')
        ..change('The quick red fox leaped over the lazy cat');
      expect(text.value, equals('The quick red fox leaped over the lazy cat'));
    });

    test('change works with empty string to text', () {
      text.change('Hello World');
      expect(text.value, equals('Hello World'));
    });

    test('change works with text to empty string', () {
      text
        ..insert(0, 'Hello World')
        ..change('');
      expect(text.value, equals(''));
    });

    test('change within transaction generates operations efficiently', () {
      text.insert(0, 'ABC');
      final initialChanges = doc.exportChanges().length;

      doc.runInTransaction(() {
        text.change('AXBYCZ');
      });

      final newChanges = doc.exportChanges().length;
      expect(text.value, equals('AXBYCZ'));
      // Should have generated insert operations for X, Y, Z
      expect(newChanges, greaterThan(initialChanges));
    });

    test('length returns correct text length', () {
      text.insert(0, 'Hello World');
      expect(text.length, equals(11));
    });

    test('value uses cached state when version matches', () {
      text.insert(0, 'Hello');
      final value1 = text.value;
      final value2 = text.value;
      expect(identical(value1, value2), isTrue);
    });

    test('should compound consecutive forward deletes (Delete key)', () {
      text.insert(0, 'Hello World');
      final before = doc.exportChanges().length;

      doc.runInTransaction(() {
        text
          ..delete(5, 1)
          ..delete(5, 5);
      });

      expect(text.value, equals('Hello'));
      // The two deletes collapse into a single change.
      expect(doc.exportChanges().length, before + 1);
    });

    test('should compound consecutive backward deletes (Backspace)', () {
      text.insert(0, 'Hello World');
      final before = doc.exportChanges().length;

      doc.runInTransaction(() {
        // Backspace at the end, repeatedly.
        text
          ..delete(10, 1)
          ..delete(9, 1)
          ..delete(8, 1);
      });

      expect(text.value, equals('Hello Wo'));
      expect(doc.exportChanges().length, before + 1);
    });

    test('value maintains cache across multiple reads', () {
      text.insert(0, 'Hello');
      final value1 = text.value;
      final value2 = text.value;
      final value3 = text.value;

      expect(identical(value1, value2), isTrue);
      expect(identical(value2, value3), isTrue);
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
      text
        ..insert(0, 'Hello') // Hello
        ..insert(5, ' World') // Hello World
        ..delete(5, 1) // HelloWorld
        ..insert(5, ' Beautiful ') // Hello Beautiful World
        ..delete(0, 6); // Beautiful World
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
      doc2.binaryImportChanges(doc1.binaryExportChanges());
      doc1.binaryImportChanges(doc2.binaryExportChanges());

      // Both documents should have the same state
      expect(text1.value, equals(text2.value));
      expect(text1.value, contains('Hello'));
      expect(text1.value, contains('World'));
      expect(
        text1.value == 'HelloWorld' || text1.value == 'WorldHello',
        isTrue,
      );
    });

    test('should be able to create snapshot', () {
      text
        ..insert(0, 'Hello')
        ..insert(5, ' World')
        ..delete(5, 1);

      final snapshot = doc.takeSnapshot();

      expect(snapshot.id, isString);
      expect(
        snapshot.versionVector.entries,
        isIterable<dynamic>().having(
          (el) =>
              el.map((e) => (e as MapEntry<PeerId, HybridLogicalClock>).key),
          'keys',
          equals([author]),
        ),
      );
      expect(snapshot.data, isMap);
      final blob = snapshot.data[handlerId]!;
      // The blob leads with its own version, under the one the wrapper
      // carries, and the text follows it.
      expect(blob[0], equals(1));
      expect(
        utf8.decode(Uint8List.sublistView(blob, 1)),
        equals('HelloWorld'),
      );
    });

    group('non-BMP round-trip', () {
      test('change() replaces a whole emoji, not a surrogate half', () {
        final doc1 = CRDTDocument();
        final text1 = CRDTTextHandler(doc1, 'text')..insert(0, 'a😀b');

        final doc2 = CRDTDocument(documentId: doc1.documentId);
        final text2 = CRDTTextHandler(doc2, 'text');
        doc2.importChanges(doc1.exportChanges());

        text1.change('a😃b');
        doc2.importChanges(doc1.exportChanges());

        expect(text1.value, equals('a😃b'));
        expect(text2.value, equals('a😃b'));
        expect(text2.value.codeUnits, equals('a😃b'.codeUnits));
      });

      test('an emoji is one indivisible position', () {
        final doc = CRDTDocument();
        final text = CRDTTextHandler(doc, 'text')..insert(0, 'a😀b');

        // Three runes, even though the string is four code units long.
        expect(text.length, equals(3));
        expect(text.value.length, equals(4));

        // Deleting the single position the emoji occupies removes all of it.
        text.delete(1, 1);
        expect(text.value, equals('ab'));
      });

      test(
          'two peers concurrently inserting either side of an emoji never '
          'produce mojibake or an unpaired surrogate', () {
        // Under the old UTF-16 code-unit unit, offset 2 sat between the two
        // surrogate halves of the emoji: inserting there split it. Under
        // runes that offset does not exist; the closest valid positions are
        // rune 1 (just before the emoji) and rune 2 (just after it).
        final peerA = CRDTDocument();
        final textA = CRDTTextHandler(peerA, 'text')..insert(0, 'a😀b');

        final peerB = CRDTDocument(documentId: peerA.documentId);
        final textB = CRDTTextHandler(peerB, 'text');
        peerB.importChanges(peerA.exportChanges());

        textA.insert(1, 'X'); // just before the emoji
        textB.insert(2, 'Y'); // just after the emoji

        peerB.importChanges(peerA.exportChanges());
        peerA.importChanges(peerB.exportChanges());

        expect(textA.value, equals(textB.value));
        expect(textA.value, contains('😀'));
        expect(textA.value, isNot(contains('�')));
      });
    });
  });
}
