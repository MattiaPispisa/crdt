import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_socket_sync/src/server_client/server/document_catalog.dart';
import 'package:crdt_socket_sync/src/server_client/server/persistent_server_registry.dart';
import 'package:persistence_conformance/persistence_conformance.dart';
import 'package:test/test.dart';

/// No delay, so a test never waits on a timer it does not care about.
const Duration _now = Duration.zero;

/// Storages that outlive the registry holding them.
///
/// One instance per document id, handed to every registry that asks. That is
/// what a restart looks like from the registry's side: a new registry, the
/// same bytes.
class _Backend {
  final Map<String, _CountingChangeStorage> changes =
      <String, _CountingChangeStorage>{};
  final Map<String, InMemorySnapshotStorage> snapshots =
      <String, InMemorySnapshotStorage>{};

  CRDTDocumentStorage open(String documentId) {
    return CRDTDocumentStorage(
      changes: changes.putIfAbsent(
        documentId,
        () => _CountingChangeStorage(InMemoryChangeStorage(documentId)),
      ),
      snapshots: snapshots.putIfAbsent(
        documentId,
        () => InMemorySnapshotStorage(documentId),
      ),
    );
  }
}

/// A change storage that counts the writes it is asked for.
class _CountingChangeStorage implements CRDTChangeStorage {
  _CountingChangeStorage(this._inner);

  final CRDTChangeStorage _inner;

  /// How many times [saveChanges] was called, whatever each batch held.
  int saveCalls = 0;

  @override
  String get documentId => _inner.documentId;

  @override
  FutureOr<void> saveChange(Change change) => _inner.saveChange(change);

  @override
  FutureOr<void> saveChanges(List<Change> changes) {
    saveCalls++;
    return _inner.saveChanges(changes);
  }

  @override
  FutureOr<List<Change>> getChanges({
    VersionVector? newerThan,
    VersionVector? upTo,
  }) =>
      _inner.getChanges(newerThan: newerThan, upTo: upTo);

  @override
  FutureOr<bool> deleteChange(Change change) => _inner.deleteChange(change);

  @override
  FutureOr<int> deleteChanges(List<Change> changes) =>
      _inner.deleteChanges(changes);

  @override
  FutureOr<void> clear() => _inner.clear();

  @override
  FutureOr<int> get count => _inner.count;
}

/// A change written by somebody else, ready to be applied.
List<Change> _authored(void Function(CRDTListHandler<String> list) edit) {
  final document = CRDTDocument(peerId: PeerId.generate());
  edit(CRDTListHandler<String>(document, 'list'));
  return document.exportChanges();
}

void main() {
  late _Backend backend;
  late InMemoryServerDocumentCatalog catalog;

  PersistentServerRegistry build({
    int? compactAfter,
    Duration writeDelay = _now,
    bool storePeerIds = false,
  }) {
    return PersistentServerRegistry(
      openStorage: backend.open,
      catalog: catalog,
      openPeerIdStorage:
          storePeerIds ? (id) => InMemoryPeerIdStorage(id) : null,
      writeDelay: writeDelay,
      compactAfter: compactAfter,
    );
  }

  setUp(() {
    backend = _Backend();
    catalog = InMemoryServerDocumentCatalog();
    InMemoryPeerIdStorage.reset();
  });

  group('PersistentServerRegistry', () {
    test('answers null and false for a document nobody added', () async {
      final registry = build();
      addTearDown(registry.close);

      expect(await registry.hasDocument('doc'), isFalse);
      expect(await registry.getDocument('doc'), isNull);
      expect(await registry.getLatestSnapshot('doc'), isNull);
      expect(await registry.documentCount, 0);
    });

    test('a document comes back after a restart', () async {
      final first = build();
      await first.addDocument('doc');
      for (final change in _authored((list) => list.insert(0, 'a'))) {
        await first.applyChange('doc', change);
      }
      await first.close();

      // A new registry, the same storage.
      final second = build();
      addTearDown(second.close);

      final document = (await second.getDocument('doc'))!;
      expect(CRDTListHandler<String>(document, 'list').value, ['a']);
    });

    test('a burst of changes is one write, not one write each', () async {
      final registry = build(writeDelay: const Duration(milliseconds: 50));
      addTearDown(registry.close);
      await registry.addDocument('doc');

      final changes = _authored(
        (list) => list
          ..insert(0, 'a')
          ..insert(1, 'b')
          ..insert(2, 'c'),
      );
      for (final change in changes) {
        await registry.applyChange('doc', change);
      }

      // Nothing is written yet: the delay is still running.
      expect(backend.changes['doc']!.saveCalls, 0);

      await registry.createSnapshot('doc');
      // The three changes went down together, and the snapshot's prune wrote
      // the survivors once more.
      expect(backend.changes['doc']!.saveCalls, lessThan(3));
    });

    test('a duplicate change is reported as such', () async {
      final registry = build();
      addTearDown(registry.close);
      await registry.addDocument('doc');

      final change = _authored((list) => list.insert(0, 'a')).single;

      expect(await registry.applyChange('doc', change), isTrue);
      expect(await registry.applyChange('doc', change), isFalse);
    });

    test('a change with missing dependencies throws through', () async {
      final registry = build();
      addTearDown(registry.close);
      await registry.addDocument('doc');

      // The second of two dependent changes, applied without the first. The
      // server needs this to reach it: it is how an out-of-sync client is
      // found.
      final orphan = _authored(
        (list) => list
          ..insert(0, 'a')
          ..insert(1, 'b'),
      )[1];

      await expectLater(
        () => registry.applyChange('doc', orphan),
        throwsA(isA<CausallyNotReadyException>()),
      );
    });

    test('createSnapshot stores the snapshot before it returns', () async {
      final registry = build();
      addTearDown(registry.close);
      await registry.addDocument('doc');
      for (final change in _authored((list) => list.insert(0, 'a'))) {
        await registry.applyChange('doc', change);
      }

      final snapshot = await registry.createSnapshot('doc');

      // On the storage, not just in the document: a caller broadcasting this
      // needs it to survive a crash.
      expect(
        await backend.snapshots['doc']!.getLatestSnapshot(),
        isNotNull,
      );
      expect(await registry.getLatestSnapshot('doc'), snapshot);
    });

    test('getLatestSnapshot picks the newest, not the last written', () async {
      final registry = build();
      addTearDown(registry.close);
      await registry.addDocument('doc');
      for (final change in _authored((list) => list.insert(0, 'a'))) {
        await registry.applyChange('doc', change);
      }
      final newest = await registry.createSnapshot('doc');

      // An older snapshot written afterwards, the way an interrupted write
      // leaves one behind.
      final older = CRDTDocument(documentId: 'doc').takeSnapshot();
      backend.snapshots['doc']!.saveSnapshot(older);

      expect(await registry.getLatestSnapshot('doc'), newest);
    });

    test('compactAfter snapshots on its own', () async {
      final registry = build(compactAfter: 2);
      addTearDown(registry.close);
      await registry.addDocument('doc');

      final taken = <String>[];
      registry.snapshots.listen((event) => taken.add(event.documentId));

      for (final change in _authored(
        (list) => list
          ..insert(0, 'a')
          ..insert(1, 'b')
          ..insert(2, 'c'),
      )) {
        await registry.applyChange('doc', change);
      }
      // Lets the write, the snapshot and the prune settle.
      await registry.createSnapshot('doc');

      expect(taken, contains('doc'));
      // The prune dropped what the snapshot covers.
      expect(await backend.changes['doc']!.count, lessThan(3));
    });

    test('an explicit author seeds the stored id, and never beats it',
        () async {
      final chosen = PeerId.generate();
      final first = build(storePeerIds: true);
      await first.addDocument('doc', author: chosen);
      expect((await first.getDocument('doc'))!.peerId, chosen);
      await first.close();

      // A second add naming somebody else must not fork the identity: the
      // document already wrote under the first one.
      final second = build(storePeerIds: true);
      addTearDown(second.close);
      await second.addDocument('doc', author: PeerId.generate());

      expect((await second.getDocument('doc'))!.peerId, chosen);
    });

    test('the peer id survives a restart when one is stored', () async {
      final first = build(storePeerIds: true);
      await first.addDocument('doc');
      final before = (await first.getDocument('doc'))!.peerId;
      await first.close();

      final second = build(storePeerIds: true);
      addTearDown(second.close);

      expect((await second.getDocument('doc'))!.peerId, before);
    });

    test('two callers arriving together share one open', () async {
      final registry = build();
      addTearDown(registry.close);
      await registry.addDocument('doc');
      await registry.close();

      final reopened = build();
      addTearDown(reopened.close);

      final both = await Future.wait([
        reopened.getDocument('doc'),
        reopened.getDocument('doc'),
      ]);

      expect(both.first, same(both.last));
    });

    test('removeDocument forgets it, and the catalog with it', () async {
      final registry = build();
      addTearDown(registry.close);
      await registry.addDocument('doc');

      await registry.removeDocument('doc');

      expect(await registry.hasDocument('doc'), isFalse);
      expect(await catalog.documentIds, isEmpty);
      expect(await registry.documentCount, 0);
    });

    test('addDocument twice keeps the first document', () async {
      final registry = build();
      addTearDown(registry.close);

      await registry.addDocument('doc');
      final first = await registry.getDocument('doc');
      await registry.addDocument('doc');

      expect(await registry.getDocument('doc'), same(first));
      expect(await registry.documentCount, 1);
    });
  });
}
