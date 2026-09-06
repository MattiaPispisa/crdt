import 'package:crdt_lf/crdt_lf.dart';
import 'package:persistence_conformance/src/fixtures.dart';
import 'package:test/test.dart';

void main() {
  late ConformanceFixtures fixtures;

  setUp(() {
    fixtures = ConformanceFixtures('doc');
  });

  /// A document holding [changes] and nothing else.
  CRDTDocument rebuilt(List<Change> changes) =>
      CRDTDocument(documentId: 'doc')..importChanges(changes);

  group('ConformanceFixtures.changes', () {
    test('gives as many changes as asked, all different', () {
      final changes = fixtures.changes(3);

      expect(changes, hasLength(3));
      expect(changes.map((c) => c.id.toString()).toSet(), hasLength(3));
    });

    test('a second call gives new ones, not the ones before', () {
      final first = fixtures.changes(2);
      final second = fixtures.changes(3);

      expect(second, hasLength(3));
      expect(
        second.map((c) => c.id.toString()).toSet()
          ..retainAll(first.map((c) => c.id.toString())),
        isEmpty,
        reason: 'the suite stores both batches and counts them apart',
      );
    });

    test('the text really carries the emoji', () {
      final changes = fixtures.changes(2);

      final text = CRDTFugueTextHandler(rebuilt(changes), 'text');

      expect(text.value, 'a🌍0a🌍1');
    });
  });

  group('ConformanceFixtures.complexChange', () {
    test('is one change, and the nested value comes back whole', () {
      final change = fixtures.complexChange();

      final map = CRDTMapHandler<Object>(rebuilt([change]), 'map');

      expect(map.value['nested'], {
        'list': <Object>[1, 'two', 3.5, true],
        'text': 'ciao 🌍',
      });
    });
  });

  group('ConformanceFixtures.snapshot', () {
    test('holds what the document holds when it is taken', () {
      fixtures.changes(2);
      final snapshot = fixtures.snapshot();
      fixtures.changes(1);

      final document = CRDTDocument(documentId: 'doc')
        ..importSnapshot(snapshot);

      expect(
        CRDTFugueTextHandler(document, 'text').value,
        'a🌍0a🌍1',
        reason: 'the change written after it is not in there',
      );
    });
  });

  group('ConformanceFixtures.expectEveryHandler', () {
    /// Runs the check and returns the pairs that did not match.
    List<String> mismatches(CRDTDocument document) {
      final found = <String>[];
      ConformanceFixtures.expectEveryHandler(document, (actual, expected) {
        if (actual.toString() != expected.toString()) {
          found.add('$actual != $expected');
        }
      });
      return found;
    }

    test('passes on a document rebuilt from everyHandler', () {
      final document = rebuilt(fixtures.everyHandler());

      expect(mismatches(document), isEmpty);
    });

    test('fails on a document that holds nothing', () {
      // The check every adapter leans on. If it passed here it would pass on
      // a storage that lost the whole log, and every adapter would look
      // conformant while storing nothing.
      expect(
        mismatches(CRDTDocument(documentId: 'doc')),
        hasLength(6),
        reason: 'one mismatch per handler kind',
      );
    });
  });
}
