import 'package:test/test.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../../helpers/matcher.dart';

void main() {
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

    test('value uses cached state when version matches', () {
      text.insert(0, 'Hello');
      final value1 = text.value;
      final value2 = text.value;
      expect(identical(value1, value2), isTrue);
    });

    test('value recomputes when version changes', () {
      text.insert(0, 'Hello');
      final value1 = text.value;
      text.insert(5, ' World');
      final value2 = text.value;
      expect(identical(value1, value2), isFalse);
      expect(value2, equals('Hello World'));
    });

    test('value recomputes after cache invalidation', () {
      text.insert(0, 'Hello');
      final value1 = text.value;

      // Force cache invalidation
      text.insert(5, ' World');

      final value2 = text.value;
      expect(identical(value1, value2), isFalse);
      expect(value2, equals('Hello World'));
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
      doc2.binaryImportChanges(doc1.binaryExportChanges());
      doc1.binaryImportChanges(doc2.binaryExportChanges());

      // Both documents should have the same state
      expect(text1.value, equals(text2.value));
      expect(text1.value, contains('Hello'));
      expect(text1.value, contains('World'));
      expect(
        text1.value == "HelloWorld" || text1.value == "WorldHello",
        isTrue,
      );
    });

    test('should be able to create snapshot', () {
      text.insert(0, 'Hello');
      text.insert(5, ' World');
      text.delete(5, 1);

      final snapshot = doc.takeSnapshot();

      expect(snapshot.id, isString);
      expect(
        snapshot.versionVector.entries,
        isIterable.having(
          (el) => el.map((e) => e.key),
          'keys',
          equals([author]),
        ),
      );
      expect(snapshot.data, isMap);
      expect(snapshot.data[handlerId], equals('HelloWorld'));
    });

    test('should be able to continue from snapshot', () {
      text.insert(0, 'Hello');
      text.insert(5, ' World');
      text.delete(5, 1);

      doc.takeSnapshot();

      text.insert(0, 'Beautiful');

      expect(text.value, equals('BeautifulHelloWorld'));
    });

    test('operations from different peers merge correctly using snapshots', () {
      final doc1 = CRDTDocument();
      final doc2 = CRDTDocument();
      final text1 = CRDTTextHandler(doc1, 'test-text');
      final text2 = CRDTTextHandler(doc2, 'test-text');

      text1.insert(0, 'Hello');
      text2.insert(0, 'World');

      doc1.importChanges(doc2.exportChanges());
      doc2.importChanges(doc1.exportChanges());

      final snapshot1 = doc1.takeSnapshot();
      final snapshot2 = doc2.takeSnapshot();

      // Merge changes
      doc2.importSnapshot(snapshot1);
      doc1.importSnapshot(snapshot2);

      // Both documents should have the same state.
      // snapshot does not preserve changes so the newest snapshot is used.
      expect(text1.value, equals(text2.value));
      expect(text1.value, contains('World'));
      expect(text2.value, contains('Hello'));
      expect(
        text1.value == "HelloWorld" || text1.value == "WorldHello",
        isTrue,
      );
    });

    test(
      'operations from different peers merge correctly using snapshots ',
      () {
        final doc1 = CRDTDocument();
        final doc2 = CRDTDocument();
        final text1 = CRDTTextHandler(doc1, 'test-text');
        final text2 = CRDTTextHandler(doc2, 'test-text');

        text1.insert(0, 'Hello');
        text2.insert(0, 'World');

        expect(doc1.shouldApplySnapshot(doc2.takeSnapshot()), isFalse);

        final changes = doc1.exportChanges();
        final applied = doc2.importChanges(changes);

        expect(applied, equals(1));

        expect(doc2.shouldApplySnapshot(doc1.takeSnapshot()), isFalse);
        expect(doc1.shouldApplySnapshot(doc2.takeSnapshot()), isTrue);

        doc1.importSnapshot(doc2.takeSnapshot());

        expect(text1.value, equals(text2.value));
        expect(text1.value, equals('HelloWorld'));
      },
    );

    test(
      'complex scenario with 3 peers, changes, and snapshots',
      () {
        // setup
        final peerId1 = PeerId.generate();
        final peerId2 = PeerId.generate();
        final peerId3 = PeerId.generate();

        final doc1 = CRDTDocument(peerId: peerId1);
        final doc2 = CRDTDocument(peerId: peerId2);
        final doc3 = CRDTDocument(peerId: peerId3);

        final handlerId = 'complex-text';
        final text1 = CRDTTextHandler(doc1, handlerId);
        final text2 = CRDTTextHandler(doc2, handlerId);
        final text3 = CRDTTextHandler(doc3, handlerId);

        //initial edits
        text1.insert(0, 'A');
        text2.insert(0, 'B');
        text3.insert(0, 'C');

        expect(text1.value, 'A');
        expect(text2.value, 'B');
        expect(text3.value, 'C');

        // sync changes (partial: doc2 does not have changes from doc3)
        // 1 -> 2
        expect(doc2.importChanges(doc1.exportChanges()), equals(1));
        // 2 -> 3
        expect(doc3.importChanges(doc2.exportChanges()), equals(2));
        // 3 -> 1
        expect(doc1.importChanges(doc3.exportChanges()), equals(2));

        // check convergence
        expect(text1.value.length, 3);
        expect(text1.value, equals(text3.value));
        expect(text1.value, equals(text3.value));

        expect(text1.value, contains('A'));
        expect(text1.value, contains('B'));
        expect(text1.value, contains('C'));

        expect(text1.value, isNot(equals(text2.value)));

        //concurrent edits
        text1.insert(text1.length, 'X');
        text2.delete(0, 1);
        text3.insert(0, 'Y');

        // sync all changes
        var changes1 = doc1.exportChanges();
        var changes2 = doc2.exportChanges();
        var changes3 = doc3.exportChanges();

        doc1.importChanges([...changes2, ...changes3]);
        doc2.importChanges([...changes1, ...changes3]);
        doc3.importChanges([...changes1, ...changes2]);

        expect(text1.value, equals(text2.value));
        expect(text1.value, equals(text3.value));
        expect(text2.value, equals(text3.value));
        final convergedValue = text1.value;
        expect(
          convergedValue == 'YBAX' ||
              convergedValue == 'BCAX' ||
              convergedValue == 'CBAX',
          isTrue,
        );

        // take snapshot and sync
        final snapshot1 = doc1.takeSnapshot();

        // Verify snapshot data (simple check)
        expect(snapshot1.data[handlerId], isNotNull);
        expect(snapshot1.data[handlerId], equals(convergedValue));

        // Check if snapshots should be applied
        expect(doc2.shouldApplySnapshot(snapshot1), isTrue);
        expect(doc3.shouldApplySnapshot(snapshot1), isTrue);

        final applied2 = doc2.importSnapshot(snapshot1);
        final applied3 = doc3.importSnapshot(snapshot1);

        expect(applied2, isTrue);
        expect(applied3, isTrue);

        // edits post-snapshot & final sync
        text2.insert(0, 'Z'); // doc2 state diverges
        text3.delete(text3.length - 1, 1); // doc3 state diverges

        // sync all changes again
        changes1 =
            doc1.exportChanges(); // Should be empty as no new changes in doc1
        changes2 =
            doc2.exportChanges(); // Should contain only 'Z' insertion ops
        changes3 = doc3.exportChanges(); // Should contain only deletion ops

        expect(changes1, isEmpty);
        expect(changes2, isNotEmpty);
        expect(changes3, isNotEmpty);

        doc1.importChanges([...changes2, ...changes3]);
        doc2.importChanges([...changes1, ...changes3]);
        doc3.importChanges([...changes1, ...changes2]);

        // Final convergence check
        expect(text1.value, equals(text2.value));
        expect(text2.value, equals(text3.value));
      },
    );
  });
}
