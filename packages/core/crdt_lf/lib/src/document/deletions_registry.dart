part of 'document.dart';

const String _deletedHandlersKey = SnapshotRecords.deletedHandlersKey;

/// The ids of the deleted handlers, under the reserved id.
///
/// Its snapshot blob is the tagless OR-set layout (version 1): the tags only
/// serve a remove, and nothing removes a delete.
final class _DeletionsRegistry extends CRDTORSetHandler<String> {
  _DeletionsRegistry(BaseCRDTDocument doc)
      : super.fromSpec(
          doc,
          _deletedHandlersKey,
          spec: spec,
          valueCodec: _codec,
        );

  static const ValueCodec<String> _codec = JsonValueCodec<String>();

  static const int _blobVersion = SnapshotRecords.deletionsVersion;

  static final HandlerSpec<_DeletionsRegistry> spec = HandlerSpec(
    _deletedHandlersKey,
    (doc, id) => _DeletionsRegistry(doc),
    formats: const HandlerFormats(
      operationKinds: {OperationType.kindInsert, OperationType.kindDelete},
      blobVersions: BlobVersionRange.single(_blobVersion),
    ),
  );

  /// The envelope prefix of a deletions change: spots one without a decode on
  /// the apply path.
  static final Uint8List _prefix = () {
    final out = BytesBuilder(copy: false);
    OperationEnvelopeCodec.writeEnvelopePrefix(
      out,
      _deletedHandlersKey,
      _deletedHandlersKey,
    );
    return out.toBytes();
  }();

  /// Whether [change] is an operation of the deletions registry.
  static bool isDeletionsChange(Change change) {
    final payload = change.payloadBytes();
    return payload.length > _prefix.length && startsWithBytes(payload, _prefix);
  }

  @override
  int get snapshotBlobVersion => _blobVersion;

  @override
  Uint8List getSnapshotState() {
    final ids = value;
    final out = snapshotHeader();
    UVarint.write(ids.length, out);
    for (final id in ids) {
      UVarint.writeBytes(_codec.encode(id), out);
    }
    return out.toBytes();
  }
}
