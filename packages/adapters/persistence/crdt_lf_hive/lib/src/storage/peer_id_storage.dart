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
  CRDTHivePeerIdStorage(this.box, this.documentId);

  /// The Hive box used for storing peer ids.
  final Box<String> box;

  @override
  final String documentId;

  @override
  PeerId? getPeerId() {
    final stored = box.get(documentId);
    return stored == null ? null : PeerId.parse(stored);
  }

  @override
  Future<void> savePeerId(PeerId peerId) {
    return box.put(documentId, peerId.toString());
  }
}
