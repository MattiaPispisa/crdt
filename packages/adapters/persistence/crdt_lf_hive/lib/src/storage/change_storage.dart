import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';

/// Stores [Change] objects in a Hive [box].
///
/// The box holds one document: [CRDTHive.openChangeStorageForDocument] names
/// it after the document id, so nothing filters by document here.
class CRDTHiveChangeStorage implements CRDTChangeStorage {
  /// Creates a new [CRDTHiveChangeStorage] instance.
  ///
  /// [box] is the Hive box that will be used to store [Change] objects.
  ///
  /// [documentId] is the unique identifier
  /// for the document these changes belong to.
  CRDTHiveChangeStorage(this.box, this.documentId);

  /// The Hive box used for storing [Change] objects.
  final Box<Change> box;

  @override
  final String documentId;

  /// Generates a key for storing changes.
  String _getChangeKey(Change change) => change.id.toString();

  @override
  Future<void> saveChange(Change change) {
    final key = _getChangeKey(change);
    return box.put(key, change).then((_) => null);
  }

  @override
  Future<void> saveChanges(List<Change> changes) {
    final entries = <String, Change>{};
    for (final change in changes) {
      final key = _getChangeKey(change);
      entries[key] = change;
    }
    return box.putAll(entries).then((_) => null);
  }

  @override
  Future<List<Change>> getChanges() async {
    return box.values.toList();
  }

  @override
  Future<bool> deleteChange(Change change) async {
    final key = _getChangeKey(change);
    if (box.containsKey(key)) {
      await box.delete(key);
      return true;
    }
    return false;
  }

  @override
  Future<int> deleteChanges(List<Change> changes) async {
    final existingKeys =
        changes.map(_getChangeKey).where(box.containsKey).toList();
    await box.deleteAll(existingKeys);
    return existingKeys.length;
  }

  @override
  Future<void> clear() async {
    await box.clear();
  }

  @override
  Future<int> get count async => box.length;
}
