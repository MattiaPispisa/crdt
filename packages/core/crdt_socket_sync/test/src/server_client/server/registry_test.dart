import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/server_client/server/registry.dart';
import 'package:test/test.dart';

void main() {
  group('DocumentSnapshotFeed', () {
    late DocumentSnapshotFeed feed;
    late List<ServerSnapshot> seen;
    late List<ServerSnapshot> taken;

    setUp(() {
      seen = [];
      taken = [];
      feed = DocumentSnapshotFeed()..snapshots.listen(taken.add);
    });

    tearDown(() => feed.close());

    test('reports tracked documents only once started', () async {
      final document = CRDTDocument(documentId: 'doc');
      feed.track('doc', document);

      document.takeSnapshot();
      await pumpEventQueue();
      expect(taken, isEmpty);

      feed.start(onSnapshot: seen.add);
      final snapshot = document.takeSnapshot();
      await pumpEventQueue();

      expect(taken, [(documentId: 'doc', snapshot: snapshot)]);
      expect(seen, taken);
    });

    test('reports a snapshot once onSnapshot completes, in order', () async {
      final stored = Completer<void>();
      final document = CRDTDocument(documentId: 'doc');
      var calls = 0;
      feed
        ..track('doc', document)
        ..start(onSnapshot: (_) => calls++ == 0 ? stored.future : null);

      final first = document.takeSnapshot();
      final second = document.takeSnapshot();
      await pumpEventQueue();
      expect(taken, isEmpty);

      stored.complete();
      await pumpEventQueue();

      expect(taken.map((event) => event.snapshot), [first, second]);
    });

    test('drops a snapshot onSnapshot fails on', () async {
      final document = CRDTDocument(documentId: 'doc');
      feed
        ..track('doc', document)
        ..start(onSnapshot: (_) => throw StateError('disk full'));

      document.takeSnapshot();
      await pumpEventQueue();

      expect(taken, isEmpty);
    });

    test('watches a document tracked after start at once', () async {
      feed.start();
      final document = CRDTDocument(documentId: 'doc');
      feed.track('doc', document);

      document.takeSnapshot();
      await pumpEventQueue();

      expect(taken, hasLength(1));
    });

    test('a second start and a second track add no watcher', () async {
      final document = CRDTDocument(documentId: 'doc');
      feed
        ..track('doc', document)
        ..start()
        ..start()
        ..track('doc', document);

      document.takeSnapshot();
      await pumpEventQueue();

      expect(taken, hasLength(1));
    });

    test('stops reporting an untracked document', () async {
      final document = CRDTDocument(documentId: 'doc');
      feed
        ..track('doc', document)
        ..start();

      await feed.untrack('doc');
      document.takeSnapshot();
      await pumpEventQueue();

      expect(taken, isEmpty);
    });

    test('close ends the stream and ignores later tracks', () async {
      final done = feed.snapshots.toList();
      feed.start();
      await feed.close();
      final document = CRDTDocument(documentId: 'doc');
      feed.track('doc', document);
      document.takeSnapshot();

      expect(await done, isEmpty);
    });
  });
}
