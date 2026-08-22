import 'dart:typed_data';

/// Reads the version byte one entry of `Snapshot.data` starts with.
///
/// `Snapshot.schemaVersion` covers the wrapper: the document id, the version
/// vector, and the framing of the entries. Each entry carries a version of
/// its own, so its layout can change on its own.
class SnapshotBlob {
  /// Checks the version byte at the head of [bytes] and returns the offset of
  /// what follows it.
  ///
  /// [name] names the blob in the error message.
  ///
  /// Throws a [FormatException] on an empty buffer, and on any version other
  /// than [version]. A blob is refused whole rather than read as far as it
  /// parses: half a blob decodes into a state no other peer holds, and says
  /// nothing about it.
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
