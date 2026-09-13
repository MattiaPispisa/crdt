import 'package:crdt_lf/crdt_lf.dart';

/// What [handler] says it can read.
///
/// The kinds are the keys of [Handler.operationDecoders], so they name exactly
/// what this build dispatches. The range is
/// `minReadableSnapshotBlobVersion..snapshotBlobVersion`, of which the handler
/// writes the newest.
HandlerFormats formatsOf(Handler<dynamic> handler) {
  return HandlerFormats(
    operationKinds: handler.operationDecoders.keys.toSet(),
    blobVersions: BlobVersionRange(
      handler.minReadableSnapshotBlobVersion,
      handler.snapshotBlobVersion,
    ),
  );
}
