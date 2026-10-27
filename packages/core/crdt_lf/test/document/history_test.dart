// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('history session', () {
    late CRDTDocument document;
    late CRDTListHandler<String> listHandler;

    setUp(() {
      document = CRDTDocument();
      listHandler = CRDTListHandler<String>(
        document,
        'list',
        handlerType: 'CRDTListHandler<String>',
      );
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
        (doc) => CRDTListHandler<String>(
          doc,
          'list',
          handlerType: 'CRDTListHandler<String>',
        ),
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
      expect(
        () => viewListHandler.doc.deleteHandler(viewListHandler),
        throwsA(isA<ReadOnlyDocumentException>()),
      );
      expect(
        () => viewListHandler.doc.deleteHandlerRef(
          HandlerRef.of(viewListHandler),
        ),
        throwsA(isA<ReadOnlyDocumentException>()),
      );
      expect(
        () => viewListHandler.doc.runInTransaction(() {}),
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
        (doc) => CRDTListHandler<String>(
          doc,
          'list',
          handlerType: 'CRDTListHandler<String>',
        ),
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
        (doc) => CRDTListHandler<String>(
          doc,
          'list',
          handlerType: 'CRDTListHandler<String>',
        ),
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
        (doc) => CRDTListHandler<String>(
          doc,
          'list',
          handlerType: 'CRDTListHandler<String>',
        ),
      );
      expect(viewListHandler.value, ['Hello', 'World', 'Dart']);

      final doc2 = CRDTDocument();
      CRDTListHandler<String>(
        doc2,
        'list',
        handlerType: 'CRDTListHandler<String>',
      )
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
        (doc) => CRDTListHandler<String>(
          doc,
          'list',
          handlerType: 'CRDTListHandler<String>',
        ),
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
        (doc) => CRDTListHandler<String>(
          doc,
          'list',
          handlerType: 'CRDTListHandler<String>',
        ),
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
        (doc) => CRDTListHandler<String>(
          doc,
          'list',
          handlerType: 'CRDTListHandler<String>',
        ),
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
      CRDTListHandler<String>(
        document,
        'other',
        handlerType: 'CRDTListHandler<String>',
      ).insert(0, 'Elsewhere');

      final historySession = document.toTimeTravel();
      final viewDocument = historySession
          .getHandler<CRDTListHandler<String>, List<String>>(
            (doc) => CRDTListHandler<String>(
              doc,
              'list',
              handlerType: 'CRDTListHandler<String>',
            ),
          )
          .doc;

      expect(viewDocument.changeCountForHandler('list'), 3);
      expect(viewDocument.changeCountForHandler('other'), 1);

      historySession
        ..previous()
        ..previous();
      expect(viewDocument.changeCountForHandler('list'), 2);
      expect(viewDocument.changeCountForHandler('other'), 0);
    });

    test('the revision moves on every jump, in both directions', () {
      listHandler
        ..insert(0, 'Hello')
        ..insert(1, 'World');
      final historySession = document.toTimeTravel();
      final viewDocument = historySession
          .getHandler<CRDTListHandler<String>, List<String>>(
            (doc) => CRDTListHandler<String>(
              doc,
              'list',
              handlerType: 'CRDTListHandler<String>',
            ),
          )
          .doc;

      var seen = viewDocument.revisionForHandler('list');
      expect(viewDocument.revisionForHandler('list'), seen);

      for (final move in [historySession.previous, historySession.next]) {
        move();
        final revision = viewDocument.revisionForHandler('list');
        expect(revision, greaterThan(seen));
        seen = revision;
      }
    });

    test('a jump tells the watchers to read the value again', () async {
      listHandler
        ..insert(0, 'Hello')
        ..insert(1, 'World');
      final historySession = document.toTimeTravel();
      final view =
          historySession.getHandler<CRDTListHandler<String>, List<String>>(
        (doc) => CRDTListHandler<String>(
          doc,
          'list',
          handlerType: 'CRDTListHandler<String>',
        ),
      );
      final causes = <ResetCause>[];
      final subscription = view.watch().listen((update) {
        if (update is HandlerReset<SequenceDelta<String>>) {
          causes.add(update.cause);
        }
      });
      await Future<void>.delayed(Duration.zero);

      historySession.previous();
      expect(causes, [ResetCause.initial, ResetCause.cacheDropped]);
      expect(view.readSynced().value, ['Hello']);

      await subscription.cancel();
    });

    test('handlerById opens the handlers the history names, at any cursor', () {
      listHandler
        ..insert(0, 'Hello')
        ..insert(1, 'World');
      final historySession = document.toTimeTravel();
      final viewDocument = historySession
          .getHandler<CRDTListHandler<String>, List<String>>(
            (doc) => CRDTListHandler<String>(
              doc,
              'list',
              handlerType: 'CRDTListHandler<String>',
            ),
          )
          .doc;

      historySession.jump(0);
      final view = viewDocument.handlerById('list')! as CRDTListHandler<String>;
      expect(view.value, isEmpty);
      historySession.jump(2);
      expect(view.value, ['Hello', 'World']);

      expect(viewDocument.handlerById('unknown'), isNull);
      expect(viewDocument.handlerById('crdt_lf/deleted-handlers'), isNull);
    });

    test('handlerById builds a handler no one opened on the view', () {
      CRDTListHandler<String>(
        document,
        'other',
        handlerType: 'CRDTListHandler<String>',
      ).insert(0, 'Elsewhere');
      CRDTListHandler<String>(
        document,
        'untouched',
        handlerType: 'CRDTListHandler<String>',
      );
      final historySession = document.toTimeTravel();
      final viewDocument = historySession
          .getHandler<CRDTListHandler<String>, List<String>>(
            (doc) => CRDTListHandler<String>(
              doc,
              'list',
              handlerType: 'CRDTListHandler<String>',
            ),
          )
          .doc;

      final other =
          viewDocument.handlerById('other')! as CRDTListHandler<String>;
      expect(other.value, ['Elsewhere']);
      expect(viewDocument.handlerById('other'), same(other));
      // No change names it, only the live document had it open.
      expect(
        (viewDocument.handlerById('untouched')! as CRDTListHandler<String>)
            .value,
        isEmpty,
      );
    });

    test('the version follows the cursor', () {
      listHandler
        ..insert(0, 'Hello')
        ..insert(1, 'World');
      final first = document.exportChanges().sorted().first;

      final historySession = document.toTimeTravel();
      final viewDocument = historySession
          .getHandler<CRDTListHandler<String>, List<String>>(
            (doc) => CRDTListHandler<String>(
              doc,
              'list',
              handlerType: 'CRDTListHandler<String>',
            ),
          )
          .doc;

      expect(viewDocument.version, document.version);
      historySession.jump(1);
      expect(viewDocument.version, {first.id});
      historySession.jump(0);
      expect(viewDocument.version, isEmpty);
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
        (doc) => CRDTListHandler<String>(
          doc,
          'list',
          handlerType: 'CRDTListHandler<String>',
        ),
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

    test('a view reads the changes its snapshot carries', () {
      final listSpec = CRDTListHandler.spec<String>('carried');
      final writer = CRDTDocument();
      writer.handler(listSpec, 'carried').insert(0, 'a');
      final server = CRDTDocument()..importChanges(writer.exportChanges());
      final reader = CRDTDocument()..importSnapshot(server.takeSnapshot());

      final view = reader
          .toTimeTravel()
          .getHandler<CRDTListHandler<String>, List<String>>(
            (doc) => doc.handler(listSpec, 'carried'),
          );

      expect(view.value, ['a']);
    });

    test('a handler reads as deleted from the change that deleted it', () {
      final root = CRDTMapRefHandler(document, 'root');
      final title = root.child('title', CRDTFugueTextHandler.spec)
        ..insert(0, 'Hi');
      document.deleteHandler(title);

      final historySession = document.toTimeTravel();
      final viewRoot =
          historySession.getHandler<CRDTMapRefHandler, Map<String, HandlerRef>>(
        (doc) => CRDTMapRefHandler(doc, 'root'),
      );
      final viewTitle =
          historySession.getHandler<CRDTFugueTextHandler, FugueTextState>(
        (doc) => CRDTFugueTextHandler(doc, title.id),
      );

      expect(viewRoot.resolved, isEmpty);
      expect(viewTitle.isDeleted, isTrue);

      historySession.previous();

      expect(viewRoot.resolved, {'title': 'Hi'});
      expect(viewTitle.isDeleted, isFalse);
    });
  });
}
