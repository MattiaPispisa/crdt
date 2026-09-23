import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

// Every method below throws until it is written. The dartdoc of each
// interface in crdt_lf_persistence says what the method must do; the
// adapters crdt_lf_sqlite, crdt_lf_drift and crdt_lf_hive are three complete
// examples to copy from.

/// The database the server keeps its documents in.
class {{name.pascalCase()}}StorageBackend implements CRDTStorageBackend {
  @override
  FutureOr<CRDTDocumentStorage> storageForDocument(String documentId) {
    return CRDTDocumentStorage(
      changes: {{name.pascalCase()}}ChangeStorage(documentId),
      snapshots: {{name.pascalCase()}}SnapshotStorage(documentId),
    );
  }

  @override
  FutureOr<CRDTPeerIdStorage> peerIdStorageForDocument(String documentId) {
    return {{name.pascalCase()}}PeerIdStorage(documentId);
  }

  @override
  FutureOr<Set<String>> get documentIds => throw UnimplementedError();

  @override
  FutureOr<void> deleteDocument(String documentId) {
    throw UnimplementedError();
  }

  @override
  FutureOr<void> close() {
    throw UnimplementedError();
  }
}

/// The changes of one document.
class {{name.pascalCase()}}ChangeStorage implements CRDTChangeStorage {
  /// Creates the change storage of [documentId].
  {{name.pascalCase()}}ChangeStorage(this.documentId);

  @override
  final String documentId;

  @override
  FutureOr<void> saveChange(Change change) => throw UnimplementedError();

  @override
  FutureOr<void> saveChanges(List<Change> changes) {
    throw UnimplementedError();
  }

  @override
  FutureOr<List<Change>> getChanges({
    VersionVector? newerThan,
    VersionVector? upTo,
  }) {
    throw UnimplementedError();
  }

  @override
  FutureOr<bool> deleteChange(Change change) => throw UnimplementedError();

  @override
  FutureOr<int> deleteChanges(List<Change> changes) {
    throw UnimplementedError();
  }

  @override
  FutureOr<void> clear() => throw UnimplementedError();

  @override
  FutureOr<int> get count => throw UnimplementedError();
}

/// The snapshots of one document.
class {{name.pascalCase()}}SnapshotStorage implements CRDTSnapshotStorage {
  /// Creates the snapshot storage of [documentId].
  {{name.pascalCase()}}SnapshotStorage(this.documentId);

  @override
  final String documentId;

  @override
  FutureOr<void> saveSnapshot(Snapshot snapshot) {
    throw UnimplementedError();
  }

  @override
  FutureOr<void> saveSnapshots(List<Snapshot> snapshots) {
    throw UnimplementedError();
  }

  @override
  FutureOr<Snapshot?> getSnapshot(String id) => throw UnimplementedError();

  @override
  FutureOr<List<Snapshot>> getSnapshots() => throw UnimplementedError();

  @override
  FutureOr<bool> containsSnapshot(String id) => throw UnimplementedError();

  @override
  FutureOr<bool> deleteSnapshot(String id) => throw UnimplementedError();

  @override
  FutureOr<int> deleteSnapshots(List<String> ids) {
    throw UnimplementedError();
  }

  @override
  FutureOr<void> clear() => throw UnimplementedError();

  @override
  FutureOr<int> get count => throw UnimplementedError();
}

/// The identity this device writes one document under.
class {{name.pascalCase()}}PeerIdStorage implements CRDTPeerIdStorage {
  /// Creates the identity storage of [documentId].
  {{name.pascalCase()}}PeerIdStorage(this.documentId);

  @override
  final String documentId;

  @override
  FutureOr<PeerId?> getPeerId() => throw UnimplementedError();

  @override
  FutureOr<void> savePeerId(PeerId peerId) => throw UnimplementedError();
}
