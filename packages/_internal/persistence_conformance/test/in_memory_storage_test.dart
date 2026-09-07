import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:persistence_conformance/persistence_conformance.dart';
import 'package:test/test.dart';

void main() {
  // One backend for the whole run, so asking twice for the same id gives the
  // same storage back. That is what makes an in-memory store durable enough
  // for the group that closes and reopens: closing it does nothing, and the
  // rows are still there.
  final backend = InMemoryStorageBackend();

  runDocumentStorageConformanceTests(
    name: 'InMemoryDocumentStorage',
    open: (documentId) async => backend.storageForDocument(documentId),
    synchronous: true,
    openPeerIds: (documentId) async =>
        backend.peerIdStorageForDocument(documentId),
    // Nothing to release, but it is what runs the hook an adapter with a
    // handle to close hangs on.
    dispose: (storage) async {},
  );

  // The same store, with the one thing it cannot do on its own. Nothing else
  // in this repo runs the rollback clause in memory: sqlite and drift claim
  // it, and they are checked in their own packages.
  final transactional = <String, _RollingBackStorage>{};

  runDocumentStorageConformanceTests(
    name: 'InMemoryDocumentStorage with rollback',
    open: (documentId) async => transactional.putIfAbsent(
      documentId,
      () => _RollingBackStorage(documentId),
    ),
    atomicTransactions: true,
    synchronous: true,
    openPeerIds: (documentId) async =>
        backend.peerIdStorageForDocument('rollback-$documentId'),
  );

  // The same store again, claiming nothing. It is what an adapter that keeps
  // no identity, rolls nothing back and survives no restart is checked
  // against, and it is the run where the suite reports what it skipped.
  runDocumentStorageConformanceTests(
    name: 'InMemoryDocumentStorage as a minimal adapter',
    open: (documentId) async => InMemoryDocumentStorage(documentId),
    durable: false,
    dispose: (storage) async {},
  );

  runStorageBackendConformanceTests(
    name: 'InMemoryStorageBackend',
    open: InMemoryStorageBackend.new,
    // Closing it keeps everything, so the backend it hands back is itself.
    reopen: (previous) => previous,
  );

  runStorageBackendConformanceTests(
    name: 'InMemoryStorageBackend that is not reopened',
    open: InMemoryStorageBackend.new,
  );

  group('InMemoryPeerIdStorage', () {
    test('without a map of its own, two storages see the same identities', () {
      InMemoryPeerIdStorage.reset();
      final peerId = PeerId.generate();

      InMemoryPeerIdStorage('doc').savePeerId(peerId);

      expect(
        InMemoryPeerIdStorage('doc').getPeerId(),
        peerId,
        reason: 'two openings of one database read the same row',
      );
    });

    test('reset forgets what the shared map holds', () {
      InMemoryPeerIdStorage('doc').savePeerId(PeerId.generate());

      InMemoryPeerIdStorage.reset();

      expect(InMemoryPeerIdStorage('doc').getPeerId(), isNull);
    });
  });
}

/// An in-memory storage whose [transaction] really rolls back.
///
/// It keeps what it held before the body ran and puts it back when the body
/// throws.
class _RollingBackStorage extends CRDTDocumentStorage {
  _RollingBackStorage(String documentId)
      : super(
          changes: InMemoryChangeStorage(documentId),
          snapshots: InMemorySnapshotStorage(documentId),
        );

  InMemoryChangeStorage get _changes => changes as InMemoryChangeStorage;

  InMemorySnapshotStorage get _snapshots =>
      snapshots as InMemorySnapshotStorage;

  @override
  FutureOr<T> transaction<T>(FutureOr<T> Function() body) {
    final changesBefore = _changes.getChanges();
    final snapshotsBefore = _snapshots.getSnapshots();

    void rollback() {
      _changes
        ..clear()
        ..saveChanges(changesBefore);
      _snapshots
        ..clear()
        ..saveSnapshots(snapshotsBefore);
    }

    FutureOr<T> result;
    try {
      result = body();
    } catch (_) {
      rollback();
      rethrow;
    }

    if (result is Future<T>) {
      return result.then(
        (value) => value,
        onError: (Object error, StackTrace stack) {
          rollback();
          Error.throwWithStackTrace(error, stack);
        },
      );
    }
    return result;
  }
}
