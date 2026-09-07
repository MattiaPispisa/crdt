import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';

/// Stores [Change] objects in a Hive [box].
///
/// The box holds one document: [CRDTHive.openChangeStorageForDocument] names
/// it after the document id, so nothing filters by document here. One entry
/// per change, keyed by `change.id.toString()`.
///
/// A Hive box keeps its entries in memory, so every read here answers without
/// suspending and says so in its return type. Writes go through the box
/// journal and stay asynchronous.
class CRDTHiveChangeStorage implements CRDTChangeStorage {
  /// Creates a new [CRDTHiveChangeStorage] instance.
  ///
  /// [box] is the Hive box that will be used to store [Change] objects.
  ///
  /// [documentId] is the unique identifier
  /// for the document these changes belong to.
  ///
  /// [onWrite] runs before every write that adds something.
  ///
  /// It is how [CRDTHiveBackend] learns a document exists: Hive cannot list
  /// its boxes, so the backend keeps a registry, and a document belongs on it
  /// once something about it has been stored — not merely because it was
  /// opened to be read.
  CRDTHiveChangeStorage(this.box, this.documentId, {this.onWrite});

  /// The Hive box used for storing [Change] objects.
  final Box<Change> box;

  /// Called before a write that adds something. See the constructor.
  final Future<void> Function()? onWrite;

  @override
  final String documentId;

  String _getChangeKey(Change change) => change.id.toString();

  @override
  Future<void> saveChange(Change change) async {
    await onWrite?.call();
    await box.put(_getChangeKey(change), change);
  }

  @override
  Future<void> saveChanges(List<Change> changes) async {
    if (changes.isEmpty) {
      return;
    }
    await onWrite?.call();
    await box.putAll(<String, Change>{
      for (final change in changes) _getChangeKey(change): change,
    });
  }

  /// The stored changes of this document, in no particular order.
  ///
  /// It reads the whole box and filters in memory, so a bound costs the same
  /// as no bound. The SQL adapters filter in the database instead.
  @override
  List<Change> getChanges({
    VersionVector? newerThan,
    VersionVector? upTo,
  }) {
    return filterByVersion(
      box.values.toList(),
      newerThan: newerThan,
      upTo: upTo,
    );
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
    // A set, so a change named twice in one batch is counted once: the
    // answer is how many were there, not how many were asked for.
    final existingKeys =
        changes.map(_getChangeKey).where(box.containsKey).toSet();
    await box.deleteAll(existingKeys);
    return existingKeys.length;
  }

  @override
  Future<void> clear() async {
    await box.clear();
  }

  @override
  int get count => box.length;
}
