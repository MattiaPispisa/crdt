// ignore_for_file: avoid_print just for example

// This package is the contract, not a store. A real app picks an adapter —
// `crdt_lf_hive`, `crdt_lf_drift`, `crdt_lf_sqlite` — and never depends on
// this package directly.
//
// So the example does both halves: `_MapBackend` and `_MapStorage` are the
// smallest thing that keeps the contract, and the `main` below is what your
// app writes on top of any adapter that keeps it too.
//
//     dart run example/main.dart
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

Future<void> main() async {
  final backend = _MapBackend();

  // The first session writes a line.
  await _session(backend, 'note', 'hello 🌍');

  // The second reads back what the first wrote, and appends to it. In an app
  // this is the restart: same backend, new document.
  await _session(backend, 'note', ' and again');

  // A second document, to have something to list.
  await _session(backend, 'shopping', 'milk');

  print('documents: ${(await backend.documentIds).toList()..sort()}');

  // Reading one without following it: what a list of notes shows.
  final note = await backend.readDocument('note');
  print('note reads: ${CRDTFugueTextHandler(note, 'body').value}');

  await backend.deleteDocument('shopping');
  print('after delete: ${(await backend.documentIds).toList()}');

  await backend.close();
}

/// Opens [documentId] on [backend], appends [line], and closes down.
Future<void> _session(
  _MapBackend backend,
  String documentId,
  String line,
) async {
  // Reads the storage into a document and follows it: everything written from
  // here on is stored without another line of code. The identity comes from
  // the backend too, so every session is the same author.
  final open = await backend.openDocument(documentId);
  // Built after the restore, which reads the same as building it before.
  final text = CRDTFugueTextHandler(open.document, 'body');

  print('read back: ${text.value.isEmpty ? '(empty)' : text.value}');
  // `text.length`, not `text.value.length`: the text is indexed by rune and
  // 🌍 is two code units, so the string length would overshoot the end.
  text.insert(text.length, line);

  // Writes what is still waiting. Without it the process could end before the
  // delayed write runs.
  await open.persistence.dispose();
  open.document.dispose();
}

/// The whole database, kept in a map.
///
/// The three things a backend answers: which documents it holds, what each of
/// them is made of, and how to get rid of one.
class _MapBackend implements CRDTStorageBackend {
  final Map<String, _MapStorage> _documents = <String, _MapStorage>{};
  final Map<String, PeerId> _peers = <String, PeerId>{};

  @override
  Future<Set<String>> get documentIds async =>
      <String>{..._documents.keys, ..._peers.keys};

  @override
  Future<_MapStorage> storageForDocument(String documentId) async =>
      _documents.putIfAbsent(documentId, () => _MapStorage(documentId));

  @override
  Future<CRDTPeerIdStorage> peerIdStorageForDocument(String documentId) async =>
      _MapPeerIdStorage(documentId, _peers);

  @override
  Future<void> deleteDocument(String documentId) async {
    _documents.remove(documentId);
    _peers.remove(documentId);
  }

  @override
  Future<void> close() async {}
}

class _MapPeerIdStorage implements CRDTPeerIdStorage {
  _MapPeerIdStorage(this.documentId, this._peers);

  @override
  final String documentId;

  final Map<String, PeerId> _peers;

  @override
  Future<PeerId?> getPeerId() async => _peers[documentId];

  @override
  Future<void> savePeerId(PeerId peerId) async {
    _peers[documentId] = peerId;
  }
}

/// The whole contract, kept in a map.
///
/// A real adapter stores `Change.toBytes()` and `Snapshot.toBytes()` as opaque
/// blobs, keyed by `Change.id` and `Snapshot.id`, and never reads inside them.
class _MapStorage extends CRDTDocumentStorage {
  _MapStorage(String documentId)
      : super(
          changes: _MapChangeStorage(documentId),
          snapshots: _MapSnapshotStorage(documentId),
        );

  // `close` and `transaction` both have a working default, so an adapter only
  // fills in what its backend can do. A map has nothing to release and no
  // transactions, so neither is overridden here.
}

class _MapChangeStorage implements CRDTChangeStorage {
  _MapChangeStorage(this.documentId);

  @override
  final String documentId;

  final Map<String, Change> _stored = <String, Change>{};

  @override
  Future<void> saveChange(Change change) async {
    _stored[change.id.toString()] = change;
  }

  @override
  Future<void> saveChanges(List<Change> changes) async {
    for (final change in changes) {
      await saveChange(change);
    }
  }

  @override
  Future<List<Change>> getChanges({
    VersionVector? newerThan,
    VersionVector? upTo,
  }) async =>
      filterByVersion(
        _stored.values.toList(),
        newerThan: newerThan,
        upTo: upTo,
      );

  @override
  Future<bool> deleteChange(Change change) async =>
      _stored.remove(change.id.toString()) != null;

  @override
  Future<int> deleteChanges(List<Change> changes) async {
    var deleted = 0;
    for (final change in changes) {
      if (await deleteChange(change)) {
        deleted++;
      }
    }
    return deleted;
  }

  @override
  Future<void> clear() async => _stored.clear();

  @override
  Future<int> get count async => _stored.length;
}

class _MapSnapshotStorage implements CRDTSnapshotStorage {
  _MapSnapshotStorage(this.documentId);

  @override
  final String documentId;

  final Map<String, Snapshot> _stored = <String, Snapshot>{};

  @override
  Future<void> saveSnapshot(Snapshot snapshot) async {
    _stored[snapshot.id] = snapshot;
  }

  @override
  Future<void> saveSnapshots(List<Snapshot> snapshots) async {
    for (final snapshot in snapshots) {
      await saveSnapshot(snapshot);
    }
  }

  @override
  Future<Snapshot?> getSnapshot(String id) async => _stored[id];

  @override
  Future<List<Snapshot>> getSnapshots() async => _stored.values.toList();

  @override
  Future<bool> containsSnapshot(String id) async => _stored.containsKey(id);

  @override
  Future<bool> deleteSnapshot(String id) async => _stored.remove(id) != null;

  @override
  Future<int> deleteSnapshots(List<String> ids) async {
    var deleted = 0;
    for (final id in ids) {
      if (await deleteSnapshot(id)) {
        deleted++;
      }
    }
    return deleted;
  }

  @override
  Future<void> clear() async => _stored.clear();

  @override
  Future<int> get count async => _stored.length;
}
