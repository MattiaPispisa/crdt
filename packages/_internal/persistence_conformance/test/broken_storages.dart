/// Storages that break one clause of the contract each.
///
/// **These tests are meant to fail.** The file has no `_test` suffix, so
/// `dart test` never picks it up on its own: `conformance_test.dart` runs it
/// in a subprocess and checks that each mutant made the clause it breaks go
/// red. A clause that stays green here is a clause that checks nothing, and
/// every adapter passing it is passing on nothing.
library;

import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:persistence_conformance/persistence_conformance.dart';

void main() {
  document('loses the last change of a batch', _LosesLastChange.new);
  document('gives the payload bytes back empty', _EmptiesPayload.new);
  document('says it deleted a change that was gone', _AlwaysDeleted.new);
  document('counts a delete that removed nothing', _OverCountsDeletes.new);
  document('ignores the version bounds', _IgnoresVersion.new);
  document('clears nothing', _ForgetsToClear.new);
  document('gives the snapshot bytes back empty', _EmptiesSnapshot.new);
  document('holds every snapshot id there is', _AlwaysContains.new);
  document(
    'forgets the identity it was given',
    InMemoryDocumentStorage.new,
    peerIds: _DeafPeerIdStorage.new,
  );
  document(
    'suspends on every read',
    _Suspends.new,
    synchronous: true,
  );

  backend('lists no document', _ListsNothing.new);
  backend('deletes every document at once', _DeletesEverything.new);
  backend('hands one storage to every document', _OneStorageForAll.new);
}

/// Runs the document suite against the storage [build] makes.
void document(
  String name,
  CRDTDocumentStorage Function(String documentId) build, {
  bool synchronous = false,
  CRDTPeerIdStorage Function(String documentId)? peerIds,
}) {
  final opened = <String, CRDTDocumentStorage>{};
  final kept = <String, PeerId>{};

  runDocumentStorageConformanceTests(
    name: name,
    open: (documentId) async =>
        opened.putIfAbsent(documentId, () => build(documentId)),
    synchronous: synchronous,
    openPeerIds: (documentId) async =>
        peerIds?.call(documentId) ?? InMemoryPeerIdStorage(documentId, kept),
  );
}

/// Runs the backend suite against the backend [build] makes.
void backend(String name, CRDTStorageBackend Function() build) {
  runStorageBackendConformanceTests(name: name, open: build);
}

/// A storage built on the in-memory one, with [changes] replaced.
class _BrokenChanges extends CRDTDocumentStorage {
  _BrokenChanges(String documentId, CRDTChangeStorage changes)
      : super(
          changes: changes,
          snapshots: InMemorySnapshotStorage(documentId),
        );
}

/// A storage built on the in-memory one, with [snapshots] replaced.
class _BrokenSnapshots extends CRDTDocumentStorage {
  _BrokenSnapshots(String documentId, CRDTSnapshotStorage snapshots)
      : super(
          changes: InMemoryChangeStorage(documentId),
          snapshots: snapshots,
        );
}

class _LosesLastChange extends _BrokenChanges {
  _LosesLastChange(String documentId)
      : super(documentId, _LosesLastChangeStorage(documentId));
}

class _LosesLastChangeStorage extends InMemoryChangeStorage {
  _LosesLastChangeStorage(super.documentId);

  @override
  void saveChanges(List<Change> changes) {
    super.saveChanges(
      changes.isEmpty ? changes : changes.sublist(0, changes.length - 1),
    );
  }
}

class _EmptiesPayload extends _BrokenChanges {
  _EmptiesPayload(String documentId)
      : super(documentId, _EmptiesPayloadStorage(documentId));
}

class _EmptiesPayloadStorage extends InMemoryChangeStorage {
  _EmptiesPayloadStorage(super.documentId);

  @override
  List<Change> getChanges({VersionVector? newerThan, VersionVector? upTo}) {
    return super
        .getChanges(newerThan: newerThan, upTo: upTo)
        .map(
          (change) => Change.fromPayloadBytes(
            id: change.id,
            deps: change.deps,
            author: change.author,
            payloadBytes: Uint8List(0),
          ),
        )
        .toList();
  }
}

class _AlwaysDeleted extends _BrokenChanges {
  _AlwaysDeleted(String documentId)
      : super(documentId, _AlwaysDeletedStorage(documentId));
}

class _AlwaysDeletedStorage extends InMemoryChangeStorage {
  _AlwaysDeletedStorage(super.documentId);

  @override
  bool deleteChange(Change change) {
    super.deleteChange(change);
    return true;
  }
}

class _OverCountsDeletes extends _BrokenChanges {
  _OverCountsDeletes(String documentId)
      : super(documentId, _OverCountsDeletesStorage(documentId));
}

class _OverCountsDeletesStorage extends InMemoryChangeStorage {
  _OverCountsDeletesStorage(super.documentId);

  @override
  int deleteChanges(List<Change> changes) {
    super.deleteChanges(changes);
    return changes.length;
  }
}

class _IgnoresVersion extends _BrokenChanges {
  _IgnoresVersion(String documentId)
      : super(documentId, _IgnoresVersionStorage(documentId));
}

class _IgnoresVersionStorage extends InMemoryChangeStorage {
  _IgnoresVersionStorage(super.documentId);

  @override
  List<Change> getChanges({VersionVector? newerThan, VersionVector? upTo}) =>
      super.getChanges();
}

class _ForgetsToClear extends _BrokenChanges {
  _ForgetsToClear(String documentId)
      : super(documentId, _ForgetsToClearStorage(documentId));
}

class _ForgetsToClearStorage extends InMemoryChangeStorage {
  _ForgetsToClearStorage(super.documentId);

  @override
  void clear() {}
}

class _EmptiesSnapshot extends _BrokenSnapshots {
  _EmptiesSnapshot(String documentId)
      : super(documentId, _EmptiesSnapshotStorage(documentId));
}

class _EmptiesSnapshotStorage extends InMemorySnapshotStorage {
  _EmptiesSnapshotStorage(super.documentId);

  @override
  List<Snapshot> getSnapshots() => super
      .getSnapshots()
      .map(
        (snapshot) => Snapshot(
          id: snapshot.id,
          versionVector: snapshot.versionVector,
          data: const <String, Uint8List>{},
        ),
      )
      .toList();
}

class _AlwaysContains extends _BrokenSnapshots {
  _AlwaysContains(String documentId)
      : super(documentId, _AlwaysContainsStorage(documentId));
}

class _AlwaysContainsStorage extends InMemorySnapshotStorage {
  _AlwaysContainsStorage(super.documentId);

  @override
  bool containsSnapshot(String id) => true;
}

/// A peer id storage that takes an identity and keeps nothing.
class _DeafPeerIdStorage implements CRDTPeerIdStorage {
  _DeafPeerIdStorage(this.documentId);

  @override
  final String documentId;

  @override
  PeerId? getPeerId() => null;

  @override
  void savePeerId(PeerId peerId) {}
}

class _Suspends extends _BrokenChanges {
  _Suspends(String documentId)
      : super(documentId, _SuspendingChangeStorage(documentId));
}

/// A change storage that answers every read with a [Future].
class _SuspendingChangeStorage implements CRDTChangeStorage {
  _SuspendingChangeStorage(this.documentId)
      : _inner = InMemoryChangeStorage(documentId);

  final InMemoryChangeStorage _inner;

  @override
  final String documentId;

  @override
  void saveChange(Change change) => _inner.saveChange(change);

  @override
  void saveChanges(List<Change> changes) => _inner.saveChanges(changes);

  @override
  Future<List<Change>> getChanges({
    VersionVector? newerThan,
    VersionVector? upTo,
  }) async =>
      _inner.getChanges(newerThan: newerThan, upTo: upTo);

  @override
  bool deleteChange(Change change) => _inner.deleteChange(change);

  @override
  int deleteChanges(List<Change> changes) => _inner.deleteChanges(changes);

  @override
  void clear() => _inner.clear();

  @override
  Future<int> get count async => _inner.count;
}

class _ListsNothing extends InMemoryStorageBackend {
  @override
  Set<String> get documentIds => <String>{};
}

class _DeletesEverything extends InMemoryStorageBackend {
  @override
  void deleteDocument(String documentId) {
    for (final id in documentIds.toList()) {
      super.deleteDocument(id);
    }
  }
}

class _OneStorageForAll extends InMemoryStorageBackend {
  late final InMemoryDocumentStorage _only = InMemoryDocumentStorage('only');

  @override
  InMemoryDocumentStorage storageForDocument(String documentId) => _only;
}
