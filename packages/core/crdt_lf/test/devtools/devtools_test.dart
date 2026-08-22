import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/devtools/devtools.dart';
import 'package:test/test.dart';

void main() {
  group('devtools', () {
    setUp(() {
      // Each test starts with a clean tracker — TrackedDocument.all is a
      // process-global accumulator otherwise.
      TrackedDocument.all.clear();
    });

    test('CRDTDocument constructor auto-tracks the document', () {
      final doc = CRDTDocument();
      expect(TrackedDocument.all, hasLength(1));
      expect(TrackedDocument.all.first.document, equals(doc));
    });

    test('describeDocumentsJson encodes a summary for every tracked doc', () {
      CRDTDocument();
      final doc2 = CRDTDocument();
      CRDTTextHandler(doc2, 'text').insert(0, 'hi');

      final result = describeDocumentsJson();
      final decoded = jsonDecode(result) as List<dynamic>;
      expect(decoded, hasLength(2));

      final m = decoded.first as Map<String, dynamic>;
      expect(m['id'], isA<int>());
      expect(m['documentId'], isA<String>());
      expect(m['peerId'], isA<String>());
      expect(m['changesCount'], isA<int>());
      expect(m['handlersCount'], isA<int>());
      expect(m['version'], isA<List<dynamic>>());
    });

    test('describeDocumentJson returns summary plus handler list', () {
      final doc = CRDTDocument();
      CRDTTextHandler(doc, 'text');
      CRDTListHandler<int>(doc, 'list');
      final trackedId = TrackedDocument.all.first.id;

      final result = describeDocumentJson(trackedId);
      final m = jsonDecode(result) as Map<String, dynamic>;
      expect(m['id'], equals(trackedId));
      final handlers = m['handlers'] as List<dynamic>;
      expect(handlers, hasLength(2));

      final firstHandler = handlers.first as Map<String, dynamic>;
      expect(firstHandler.containsKey('id'), isTrue);
      expect(firstHandler.containsKey('type'), isTrue);
      expect(firstHandler.containsKey('value'), isTrue);
    });

    test('describeDocumentJson returns error JSON for unknown trackedId', () {
      final result = describeDocumentJson(999999);
      final m = jsonDecode(result) as Map<String, dynamic>;
      expect(m['error'], contains('999999'));
    });

    test('describeChangesJson returns change descriptors sorted by hlc', () {
      final doc = CRDTDocument();
      CRDTTextHandler(doc, 'text')
        ..insert(0, 'a')
        ..insert(1, 'b');
      final trackedId = TrackedDocument.all.first.id;

      final result = describeChangesJson(trackedId);
      final list = jsonDecode(result) as List<dynamic>;
      expect(list, hasLength(2));

      final first = list.first as Map<String, dynamic>;
      expect(first['id'], isA<String>());
      expect(first['hlc'], isA<String>());
      expect(first['author'], isA<String>());
      expect(first['deps'], isA<List<dynamic>>());
      expect(first['payloadSize'], isA<int>());
      expect(first['bytes'], isA<String>());
    });

    test('describeChangesJson returns error JSON for unknown trackedId', () {
      final result = describeChangesJson(999999);
      final m = jsonDecode(result) as Map<String, dynamic>;
      expect(m['error'], contains('999999'));
    });

    test('describeHistoryJson returns length and changes list', () {
      final doc = CRDTDocument();
      CRDTTextHandler(doc, 'text').insert(0, 'hello');
      final trackedId = TrackedDocument.all.first.id;

      final result = describeHistoryJson(trackedId);
      final m = jsonDecode(result) as Map<String, dynamic>;
      expect(m['length'], equals(1));
      final changes = m['changes'] as List<dynamic>;
      expect(changes, hasLength(1));
      expect(changes.first, isA<Map<String, dynamic>>());
    });

    test('describeHistoryJson returns error JSON for unknown trackedId', () {
      final result = describeHistoryJson(999999);
      final m = jsonDecode(result) as Map<String, dynamic>;
      expect(m['error'], contains('999999'));
    });

    test('describeChanges returns a "<n> changes, <m> bytes (v2)" summary', () {
      final doc = CRDTDocument();
      CRDTTextHandler(doc, 'text').insert(0, 'hi');
      final summary = describeChanges(doc);
      expect(summary, matches(RegExp(r'^\d+ changes, \d+ bytes \(v2\)$')));
    });

    test('postChangedEvent on a tracked doc does not throw', () {
      final doc = CRDTDocument();
      expect(() => postChangedEvent(doc), returnsNormally);
    });
  });
}
