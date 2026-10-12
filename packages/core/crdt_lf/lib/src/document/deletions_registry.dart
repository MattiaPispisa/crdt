part of 'document.dart';

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

  static const int _blobVersion = 1;

  static final HandlerSpec<_DeletionsRegistry> spec = HandlerSpec(
    _deletedHandlersKey,
    (doc, id) => _DeletionsRegistry(doc),
    formats: const HandlerFormats(
      operationKinds: {OperationType.kindInsert, OperationType.kindDelete},
      blobVersions: BlobVersionRange.single(_blobVersion),
    ),
  );

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
