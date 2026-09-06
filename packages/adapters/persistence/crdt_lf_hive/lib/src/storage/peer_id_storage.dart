import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';

/// Stores the [PeerId] of one document in a Hive [box].
///
/// One box holds the identity of every document, keyed by document id, and
/// [CRDTHive.openPeerIdStorageForDocument] opens it. A box of its own per
/// document would cost an open for a single string.
///
/// The value is the id as text, so the box needs no [TypeAdapter].
///
/// A Hive box keeps its entries in memory, so [getPeerId] answers without
/// suspending. The write goes through the box journal and stays asynchronous.
class CRDTHivePeerIdStorage implements CRDTPeerIdStorage {
  /// Creates a new [CRDTHivePeerIdStorage] instance.
  ///
  /// [box] is the shared Hive box that holds every document's identity.
  ///
  /// [documentId] is the document this identity belongs to.
  ///
  /// [onWrite] runs before every write that adds something.
  ///
  /// It is how [CRDTHiveBackend] learns a document exists: Hive cannot list
  /// its boxes, so the backend keeps a registry, and a document belongs on it
  /// once something about it has been stored — not merely because it was
  /// opened to be read.
  CRDTHivePeerIdStorage(this.box, this.documentId, {this.onWrite});

  /// The Hive box used for storing peer ids.
  final Box<String> box;

  /// Called before a write that adds something. See the constructor.
  final Future<void> Function()? onWrite;

  @override
  final String documentId;

  @override
  PeerId? getPeerId() {
    final stored = box.get(documentId);
    return stored == null ? null : PeerId.parse(stored);
  }

  @override
  Future<void> savePeerId(PeerId peerId) async {
    await onWrite?.call();
    await box.put(documentId, peerId.toString());
  }
}
