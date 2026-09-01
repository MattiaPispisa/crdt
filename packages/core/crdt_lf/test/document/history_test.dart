import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('history session', () {
    late CRDTDocument document;
    late CRDTListHandler<String> listHandler;

    setUp(() {
      document = CRDTDocument();
      listHandler = CRDTListHandler<String>(document, 'list');
    });

    test(
        'should create a history session'
        ' with cursor at the end of the document', () {
      listHandler
        ..insert(0, 'Hello')
        ..insert(1, 'World')
        ..insert(2, 'Dart');
      final changes = document.exportChanges();
      final historySession = document.toTimeTravel();

      expect(historySession.cursor, 3);
      expect(historySession.length, changes.length);
      expect(historySession.length, 3);
    });

    test('should document be read-only in the history session', () {
      listHandler
        ..insert(0, 'Hello')
        ..insert(1, 'World')
        ..insert(2, 'Dart');
      final historySession = document.toTimeTravel();
      final viewListHandler =
          historySession.getHandler<CRDTListHandler<String>, List<String>>(
        (doc) => CRDTListHandler<String>(doc, 'list'),
      );

      expect(viewListHandler.doc.documentId, document.documentId);
      expect(viewListHandler.doc.peerId, document.peerId);
      expect(viewListHandler.doc.hlc, document.hlc);

      expect(
        () {
          viewListHandler.insert(3, 'Invalid insert');
        },
        throwsA(isA<ReadOnlyDocumentException>()),
      );
      expect(
        viewListHandler.doc.prepareMutation,
        throwsA(isA<ReadOnlyDocumentException>()),
      );
    });

    test(
        'should not change when the document is modified'
        ' - operations', () {
      listHandler
        ..insert(0, 'Hello')
        ..insert(1, 'World')
        ..insert(2, 'Dart');
      final historySession = document.toTimeTravel();
      final viewListHandler =
          historySession.getHandler<CRDTListHandler<String>, List<String>>(
        (doc) => CRDTListHandler<String>(doc, 'list'),
      );

      expect(viewListHandler.value, ['Hello', 'World', 'Dart']);

      listHandler
        ..insert(3, 'Flutter')
        ..insert(4, '!');

      expect(historySession.cursor, 3);
      expect(historySession.length, 3);

      expect(viewListHandler.value, ['Hello', 'World', 'Dart']);
      expect(historySession.length, 3);
    });

    test(
        'should not change when the document is modified'
        ' - snapshot', () {
      listHandler
        ..insert(0, 'Hello')
        ..insert(1, 'World');

      document.takeSnapshot();

      listHandler.insert(2, 'Dart');

      final historySession = document.toTimeTravel();
      final viewListHandler =
          historySession.getHandler<CRDTListHandler<String>, List<String>>(
        (doc) => CRDTListHandler<String>(doc, 'list'),
      );
      expect(viewListHandler.value, ['Hello', 'World', 'Dart']);

      listHandler.insert(3, 'Flutter');
      document.takeSnapshot();
      listHandler.insert(4, '!');

      expect(viewListHandler.value, ['Hello', 'World', 'Dart']);
      expect(historySession.length, 1);
    });

    test(
        'should not change when the document is modified'
        ' - import', () {
      listHandler
        ..insert(0, 'Hello')
        ..insert(1, 'World')
        ..insert(2, 'Dart');

      final historySession = document.toTimeTravel();
      final viewListHandler =
          historySession.getHandler<CRDTListHandler<String>, List<String>>(
        (doc) => CRDTListHandler<String>(doc, 'list'),
      );
      expect(viewListHandler.value, ['Hello', 'World', 'Dart']);

      final doc2 = CRDTDocument();
      CRDTListHandler<String>(doc2, 'list')
        ..insert(0, 'Welcome')
        ..insert(1, 'to')
        ..insert(2, 'Flutter');

      final doc2Changes = doc2.exportChanges();
      document.importChanges(doc2Changes);

      expect(viewListHandler.value, ['Hello', 'World', 'Dart']);
      expect(historySession.length, 3);
    });

    test('should be able to jump to a specific cursor position', () {
      listHandler
        ..insert(0, 'Hello')
        ..insert(1, 'World')
        ..insert(2, 'Dart');

      final historySession = document.toTimeTravel();
      final viewListHandler =
          historySession.getHandler<CRDTListHandler<String>, List<String>>(
        (doc) => CRDTListHandler<String>(doc, 'list'),
      );

      expect(viewListHandler.value, ['Hello', 'World', 'Dart']);

      historySession.jump(0);
      expect(historySession.cursor, 0);
      expect(historySession.canNext, isTrue);
      expect(historySession.canPrevious, isFalse);
      expect(viewListHandler.value, <String>[]);
      expect(historySession.length, 3);

      historySession.jump(1);
      expect(viewListHandler.value, ['Hello']);
      expect(historySession.cursor, 1);
      expect(historySession.canNext, isTrue);
      expect(historySession.canPrevious, isTrue);
      expect(historySession.length, 3);

      historySession.jump(2);
      expect(viewListHandler.value, ['Hello', 'World']);
      expect(historySession.cursor, 2);
      expect(historySession.canNext, isTrue);
      expect(historySession.canPrevious, isTrue);
      expect(historySession.length, 3);

      historySession.jump(3);
      expect(viewListHandler.value, ['Hello', 'World', 'Dart']);
      expect(historySession.cursor, 3);
      expect(historySession.canNext, isFalse);
      expect(historySession.canPrevious, isTrue);
      expect(historySession.length, 3);
    });

    test('should be able to move forward and backward', () {
      listHandler
        ..insert(0, 'Hello')
        ..insert(1, 'World')
        ..insert(2, 'Dart');

      final historySession = document.toTimeTravel();
      final viewListHandler =
          historySession.getHandler<CRDTListHandler<String>, List<String>>(
        (doc) => CRDTListHandler<String>(doc, 'list'),
      );

      expect(viewListHandler.value, ['Hello', 'World', 'Dart']);
      historySession.previous();

      expect(viewListHandler.value, ['Hello', 'World']);

      historySession
        ..next()
        ..next();
      expect(
        viewListHandler.value,
        ['Hello', 'World', 'Dart'],
        reason: 'second next should do no-op',
      );
    });

    test('should notify when the cursor changes', () async {
      listHandler
        ..insert(0, 'Hello')
        ..insert(1, 'World')
        ..insert(2, 'Dart');

      final historySession = document.toTimeTravel();

      final cursorEvents = <int>[];
      final sub = historySession.cursorStream.listen(cursorEvents.add);

      historySession.previous();
      await Future<void>.delayed(Duration.zero);
      expect(cursorEvents, [2]);

      historySession.next();
      await Future<void>.delayed(Duration.zero);
      expect(cursorEvents, [2, 3]);

      historySession.next();
      await Future<void>.delayed(Duration.zero);
      expect(
        cursorEvents,
        [2, 3],
        reason: 'no-op should not emit',
      );
      await sub.cancel();
    });

    test('should throw when registering handler in the history session', () {
      listHandler
        ..insert(0, 'Hello')
        ..insert(1, 'World')
        ..insert(2, 'Dart');

      final historySession = document.toTimeTravel();
      final viewListHandler =
          historySession.getHandler<CRDTListHandler<String>, List<String>>(
        (doc) => CRDTListHandler<String>(doc, 'list'),
      );
      expect(
        () {
          viewListHandler.insert(3, 'Flutter');
        },
        throwsA(isA<ReadOnlyDocumentException>()),
      );
    });

    test('should count changes and revisions at the cursor', () {
      listHandler
        ..insert(0, 'Hello')
        ..insert(1, 'World')
        ..insert(2, 'Dart');
      CRDTListHandler<String>(document, 'other').insert(0, 'Elsewhere');

      final historySession = document.toTimeTravel();
      final viewDocument = historySession
          .getHandler<CRDTListHandler<String>, List<String>>(
            (doc) => CRDTListHandler<String>(doc, 'list'),
          )
          .doc;

      expect(viewDocument.changeCountForHandler('list'), 3);
      expect(viewDocument.changeCountForHandler('other'), 1);
      // The frozen view has no snapshot to import, so the visible change count
      // is the whole revision signal — and it follows the cursor both ways.
      expect(viewDocument.revisionForHandler('list'), 3);

      historySession
        ..previous()
        ..previous();
      expect(viewDocument.changeCountForHandler('list'), 2);
      expect(viewDocument.changeCountForHandler('other'), 0);
      expect(viewDocument.revisionForHandler('list'), 2);

      historySession.next();
      expect(viewDocument.revisionForHandler('list'), 3);
    });

    test('should dispose the history session', () {
      listHandler
        ..insert(0, 'Hello')
        ..insert(1, 'World')
        ..insert(2, 'Dart');

      final historySession = document.toTimeTravel();
      expect(historySession.dispose, returnsNormally);
    });

    test('disposing the session ends the delta streams it handed out',
        () async {
      listHandler.insert(0, 'Hello');

      final historySession = document.toTimeTravel();
      final viewListHandler =
          historySession.getHandler<CRDTListHandler<String>, List<String>>(
        (doc) => CRDTListHandler<String>(doc, 'list'),
      );

      var done = false;
      viewListHandler.watch().listen(null, onDone: () => done = true);
      // The opening reset arrives one microtask later, so the subscription is
      // wired up only after this.
      await Future<void>.delayed(Duration.zero);

      historySession.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(done, isTrue);
    });
  });
}
