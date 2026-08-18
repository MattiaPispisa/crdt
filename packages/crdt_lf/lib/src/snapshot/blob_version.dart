import 'dart:typed_data';

/// The version byte at the head of one entry of `Snapshot.data`.
///
/// `Snapshot.schemaVersion` covers the wrapper only: the document id, the
/// version vector, and the framing of the entries. What an entry holds is the
/// business of whoever wrote it, and so is its version — a handler changes its
/// own layout without moving a byte anybody else reads.
///
/// [read] is strict on purpose. A blob written by a build with a layout this
/// one does not know is refused whole, not parsed as far as it happens to
/// work: a snapshot decoded halfway leaves a peer holding a state no other
/// peer holds, and nothing says so.
class SnapshotBlob {
  /// Checks the version byte at the head of [bytes] and returns the offset of
  /// what follows it.
  ///
  /// [name] names the blob in the error message. Throws a [FormatException] on
  /// an empty buffer and on a version this build does not write.
  static int read(
    Uint8List bytes, {
    required int version,
    required String name,
  }) {
    if (bytes.isEmpty) {
      throw FormatException('Truncated $name snapshot');
    }
    if (bytes[0] != version) {
      throw FormatException(
        'Unsupported $name snapshot version: ${bytes[0]} '
        '(this build reads $version)',
      );
    }
    return 1;
  }
}
