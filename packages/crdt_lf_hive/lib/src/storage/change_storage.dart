import 'package:crdt_lf/crdt_lf.dart';
import 'package:hive/hive.dart';

/// Storage utility for managing [Change] objects in Hive.
///
/// This class provides high-level methods for storing, retrieving, and
/// managing [Change] objects in a Hive box.
class CRDTChangeStorage {
  /// Creates a new [CRDTChangeStorage] instance.
  ///
  /// [box] is the Hive box that will be used to store [Change] objects.
  ///
  /// [documentId] is the unique identifier
  /// for the document these changes belong to.
  CRDTChangeStorage(this.box, this.documentId);

  /// The Hive box used for storing [Change] objects.
  final Box<Change> box;

  /// The unique identifier for the document these changes belong to.
  final String documentId;

  /// Generates a key for storing changes.
  String _getChangeKey(Change change) => change.id.toString();

  /// Saves a [Change] to the storage.
  ///
  /// The change is stored using a composite key (documentId_changeId).
  /// Returns the change ID that was used to store the change.
  Future<void> saveChange(Change change) {
    final key = _getChangeKey(change);
    return box.put(key, change).then((_) => null);
  }

  /// Saves multiple [Change] objects to the storage.
  ///
  /// This method is more efficient than calling [saveChange] multiple times
  /// as it performs batch operations.
  /// Returns a list of change IDs that were used to store the changes.
  Future<void> saveChanges(List<Change> changes) {
    final entries = <String, Change>{};
    for (final change in changes) {
      final key = _getChangeKey(change);
      entries[key] = change;
    }
    return box.putAll(entries).then((_) => null);
  }

  /// Retrieves all [Change] objects from the storage for this document.
  ///
  /// Returns a list of all stored changes for this document.
  List<Change> getChanges() {
    return box.values.toList();
  }

  /// Deletes a [Change] by its ID.
  ///
  /// Returns true if the change was found and deleted, false otherwise.
  Future<bool> deleteChange(Change change) async {
    final key = _getChangeKey(change);
    if (box.containsKey(key)) {
      await box.delete(key);
      return true;
    }
    return false;
  }

  /// Deletes multiple [Change] objects by their IDs.
  ///
  /// Returns the number of changes that were actually deleted.
  Future<int> deleteChanges(List<Change> changes) async {
    final existingKeys =
        changes.map(_getChangeKey).where(box.containsKey).toList();
    await box.deleteAll(existingKeys);
    return existingKeys.length;
  }

  /// Clears all [Change] objects for this document from the storage.
  ///
  /// This operation cannot be undone.
  Future<void> clear() async {
    await box.clear();
  }

  /// Returns the number of [Change] objects for this document in the storage.
  int get count => box.length;

  /// Returns true if the storage is empty for this document.
  bool get isEmpty => box.isEmpty;

  /// Returns true if the storage is not empty for this document.
  bool get isNotEmpty => box.isNotEmpty;
}
