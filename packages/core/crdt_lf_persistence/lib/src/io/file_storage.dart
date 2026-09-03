import 'dart:io';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';

/// The format version written at the head of every file.
///
/// A file written by a newer version is refused rather than misread.
const int _formatVersion = 1;

/// A [CRDTDocumentStorage] backed by one plain file.
///
/// This is local-first without a database: a document, a file, and
/// [CRDTDocumentPersistence] between them.
///
/// ```dart
/// final storage = await FileDocumentStorage.open('notes.crdt');
/// final document = CRDTDocument(documentId: storage.documentId);
/// final text = CRDTFugueTextHandler(document, 'body');
/// final persistence = await CRDTDocumentPersistence.open(document, storage);
/// ```
///
/// The whole file is held in memory and rewritten on every write, through a
/// temporary file that replaces the old one only once it is complete — so a
/// process killed mid-write leaves the previous file intact, never half of a
/// new one. Rewriting all of it is the right trade for a document a person
/// edits by hand; for a document that grows without bound, or one written from
/// several isolates, use a database adapter instead.
class FileDocumentStorage extends CRDTDocumentStorage {
  FileDocumentStorage._(this._file, String documentId, this._state)
      : super(
          changes: _FileChangeStorage(documentId, _state),
          snapshots: _FileSnapshotStorage(documentId, _state),
        );

  /// Opens the storage kept in the file at [path], creating it when it is not
  /// there yet.
  ///
  /// [documentId] names a document that has no file yet. A file that already
  /// exists carries its own id, and that one wins — so reopening always
  /// returns the same document. When neither is given the file name is used.
  ///
  /// Throws a [FileSystemException] when the file was written by a newer
  /// version of this format.
  static Future<FileDocumentStorage> open(
    String path, {
    String? documentId,
  }) async {
    final file = File(path);
    final state = _FileState();

    final id = file.existsSync()
        ? state.read(await file.readAsBytes(), path)
        : documentId ?? _nameOf(path);

    final storage = FileDocumentStorage._(file, id, state);
    state
      ..documentId = id
      ..write = storage._write;
    return storage;
  }

  static String _nameOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  final File _file;
  final _FileState _state;

  Future<void> _write() async {
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsBytes(_state.encode(), flush: true);
    await temporary.rename(_file.path);
  }

  /// Deletes the file, and everything it holds.
  Future<void> delete() async {
    _state.changes.clear();
    _state.snapshots.clear();
    if (_file.existsSync()) {
      await _file.delete();
    }
  }
}

/// What the file holds, decoded, plus the write that puts it back.
class _FileState {
  String documentId = '';
  final Map<String, Change> changes = <String, Change>{};
  final Map<String, Snapshot> snapshots = <String, Snapshot>{};

  Future<void> Function() write = () async {};

  /// Reads [bytes] into this state and returns the document id it names.
  ///
  /// Layout:
  /// - `version: uvarint`
  /// - `documentId: uvarint-prefixed utf8`
  /// - `snapshotCount: uvarint`, then that many uvarint-prefixed blobs
  /// - `changeCount: uvarint`, then that many uvarint-prefixed blobs
  String read(Uint8List bytes, String path) {
    if (bytes.isEmpty) {
      return documentId;
    }

    final version = UVarint.read(bytes, offset: 0);
    if (version.value > _formatVersion) {
      throw FileSystemException(
        'written by a newer version of crdt_lf_persistence '
        '(format ${version.value}, this build reads $_formatVersion)',
        path,
      );
    }

    final id = UVarint.readString(
      bytes,
      offset: version.nextOffset,
      what: 'document id',
    );
    documentId = id.value;

    var offset = id.nextOffset;
    final snapshotCount = UVarint.read(bytes, offset: offset);
    offset = snapshotCount.nextOffset;
    for (var i = 0; i < snapshotCount.value; i++) {
      final blob = UVarint.readBytes(bytes, offset: offset, what: 'snapshot');
      final snapshot = Snapshot.fromBytes(blob.value);
      snapshots[snapshot.id] = snapshot;
      offset = blob.nextOffset;
    }

    final changeCount = UVarint.read(bytes, offset: offset);
    offset = changeCount.nextOffset;
    for (var i = 0; i < changeCount.value; i++) {
      final blob = UVarint.readBytes(bytes, offset: offset, what: 'change');
      final change = Change.fromBytes(blob.value);
      changes[change.id.toString()] = change;
      offset = blob.nextOffset;
    }

    return documentId;
  }

  /// The bytes [read] takes back.
  Uint8List encode() {
    final out = BytesBuilder();
    UVarint.write(_formatVersion, out);
    UVarint.writeString(documentId, out);

    UVarint.write(snapshots.length, out);
    for (final snapshot in snapshots.values) {
      UVarint.writeBytes(snapshot.toBytes(), out);
    }

    UVarint.write(changes.length, out);
    for (final change in changes.values) {
      UVarint.writeBytes(change.toBytes(), out);
    }

    return out.toBytes();
  }
}

class _FileChangeStorage implements CRDTChangeStorage {
  _FileChangeStorage(this.documentId, this._state);

  @override
  final String documentId;

  final _FileState _state;

  @override
  Future<void> saveChange(Change change) => saveChanges([change]);

  @override
  Future<void> saveChanges(List<Change> changes) {
    if (changes.isEmpty) {
      return Future<void>.value();
    }
    for (final change in changes) {
      _state.changes[change.id.toString()] = change;
    }
    return _state.write();
  }

  @override
  Future<List<Change>> getChanges() async => _state.changes.values.toList();

  @override
  Future<bool> deleteChange(Change change) async =>
      await deleteChanges([change]) == 1;

  @override
  Future<int> deleteChanges(List<Change> changes) async {
    var deleted = 0;
    for (final change in changes) {
      if (_state.changes.remove(change.id.toString()) != null) {
        deleted++;
      }
    }
    if (deleted > 0) {
      await _state.write();
    }
    return deleted;
  }

  @override
  Future<void> clear() {
    if (_state.changes.isEmpty) {
      return Future<void>.value();
    }
    _state.changes.clear();
    return _state.write();
  }

  @override
  Future<int> get count async => _state.changes.length;
}

class _FileSnapshotStorage implements CRDTSnapshotStorage {
  _FileSnapshotStorage(this.documentId, this._state);

  @override
  final String documentId;

  final _FileState _state;

  @override
  Future<void> saveSnapshot(Snapshot snapshot) => saveSnapshots([snapshot]);

  @override
  Future<void> saveSnapshots(List<Snapshot> snapshots) {
    if (snapshots.isEmpty) {
      return Future<void>.value();
    }
    for (final snapshot in snapshots) {
      _state.snapshots[snapshot.id] = snapshot;
    }
    return _state.write();
  }

  @override
  Future<Snapshot?> getSnapshot(String id) async => _state.snapshots[id];

  @override
  Future<List<Snapshot>> getSnapshots() async =>
      _state.snapshots.values.toList();

  @override
  Future<bool> containsSnapshot(String id) async =>
      _state.snapshots.containsKey(id);

  @override
  Future<bool> deleteSnapshot(String id) async =>
      await deleteSnapshots([id]) == 1;

  @override
  Future<int> deleteSnapshots(List<String> ids) async {
    var deleted = 0;
    for (final id in ids) {
      if (_state.snapshots.remove(id) != null) {
        deleted++;
      }
    }
    if (deleted > 0) {
      await _state.write();
    }
    return deleted;
  }

  @override
  Future<void> clear() {
    if (_state.snapshots.isEmpty) {
      return Future<void>.value();
    }
    _state.snapshots.clear();
    return _state.write();
  }

  @override
  Future<int> get count async => _state.snapshots.length;
}
