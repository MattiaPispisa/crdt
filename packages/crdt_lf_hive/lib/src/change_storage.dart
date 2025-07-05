import 'package:hive/hive.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Storage utility for managing [Change] objects in Hive.
///
/// This class provides high-level methods for storing, retrieving, and
/// managing [Change] objects in a Hive box.
class CRDTChangeStorage {
  /// Creates a new [CRDTChangeStorage] instance.
  ///
  /// [box] is the Hive box that will be used to store [Change] objects.
  CRDTChangeStorage(this.box);

  /// The Hive box used for storing [Change] objects.
  final Box<Change> box;

  /// Saves a [Change] to the storage.
  ///
  /// The change is stored using its operation ID as the key.
  /// Returns the key that was used to store the change.
  Future<String> saveChange(Change change) async {
    final key = change.id.toString();
    await box.put(key, change);
    return key;
  }

  /// Saves multiple [Change] objects to the storage.
  ///
  /// This method is more efficient than calling [saveChange] multiple times
  /// as it performs batch operations.
  /// Returns a list of keys that were used to store the changes.
  Future<List<String>> saveChanges(List<Change> changes) async {
    final entries = <String, Change>{};
    for (final change in changes) {
      entries[change.id.toString()] = change;
    }
    await box.putAll(entries);
    return entries.keys.toList();
  }

  /// Retrieves a [Change] by its operation ID.
  ///
  /// Returns the [Change] if found, or null if not found.
  Change? getChange(OperationId operationId) {
    return box.get(operationId.toString());
  }

  /// Retrieves a [Change] by its string key.
  ///
  /// Returns the [Change] if found, or null if not found.
  Change? getChangeByKey(String key) {
    return box.get(key);
  }

  /// Retrieves all [Change] objects from the storage.
  ///
  /// Returns a list of all stored changes.
  List<Change> getAllChanges() {
    return box.values.toList();
  }

  /// Retrieves changes by author.
  ///
  /// Returns a list of all changes created by the specified [PeerId].
  List<Change> getChangesByAuthor(PeerId author) {
    return box.values.where((change) => change.author == author).toList();
  }

  /// Retrieves changes within a time range.
  ///
  /// Returns changes with timestamps between [from] and [to] (inclusive).
  List<Change> getChangesInTimeRange({
    required HybridLogicalClock from,
    required HybridLogicalClock to,
  }) {
    return box.values.where((change) {
      return change.hlc.compareTo(from) >= 0 && change.hlc.compareTo(to) <= 0;
    }).toList();
  }

  /// Retrieves changes that depend on a specific operation.
  ///
  /// Returns changes that have the specified [operationId] in their dependencies.
  List<Change> getChangesDependingOn(OperationId operationId) {
    return box.values.where((change) => change.deps.contains(operationId)).toList();
  }

  /// Deletes a [Change] by its operation ID.
  ///
  /// Returns true if the change was found and deleted, false otherwise.
  Future<bool> deleteChange(OperationId operationId) async {
    final key = operationId.toString();
    if (box.containsKey(key)) {
      await box.delete(key);
      return true;
    }
    return false;
  }

  /// Deletes a [Change] by its string key.
  ///
  /// Returns true if the change was found and deleted, false otherwise.
  Future<bool> deleteChangeByKey(String key) async {
    if (box.containsKey(key)) {
      await box.delete(key);
      return true;
    }
    return false;
  }

  /// Deletes multiple [Change] objects by their operation IDs.
  ///
  /// Returns the number of changes that were actually deleted.
  Future<int> deleteChanges(List<OperationId> operationIds) async {
    final keys = operationIds.map((id) => id.toString()).toList();
    final existingKeys = keys.where((key) => box.containsKey(key)).toList();
    await box.deleteAll(existingKeys);
    return existingKeys.length;
  }

  /// Clears all [Change] objects from the storage.
  ///
  /// This operation cannot be undone.
  Future<void> clear() async {
    await box.clear();
  }

  /// Returns the number of [Change] objects in the storage.
  int get count => box.length;

  /// Returns true if the storage is empty.
  bool get isEmpty => box.isEmpty;

  /// Returns true if the storage is not empty.
  bool get isNotEmpty => box.isNotEmpty;

  /// Returns all keys in the storage.
  Iterable<String> get keys => box.keys.cast<String>();

  /// Checks if a [Change] with the given operation ID exists.
  bool containsChange(OperationId operationId) {
    return box.containsKey(operationId.toString());
  }

  /// Gets the most recent [Change] by timestamp.
  ///
  /// Returns the change with the highest [HybridLogicalClock] value,
  /// or null if the storage is empty.
  Change? getMostRecentChange() {
    if (isEmpty) return null;
    return box.values.reduce((a, b) => a.hlc.compareTo(b.hlc) > 0 ? a : b);
  }

  /// Gets the oldest [Change] by timestamp.
  ///
  /// Returns the change with the lowest [HybridLogicalClock] value,
  /// or null if the storage is empty.
  Change? getOldestChange() {
    if (isEmpty) return null;
    return box.values.reduce((a, b) => a.hlc.compareTo(b.hlc) < 0 ? a : b);
  }

  /// Gets changes sorted by timestamp.
  ///
  /// Returns all changes sorted by their [HybridLogicalClock] in ascending order.
  List<Change> getChangesSortedByTime() {
    final changes = getAllChanges();
    changes.sort((a, b) => a.hlc.compareTo(b.hlc));
    return changes;
  }
} 