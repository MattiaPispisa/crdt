import 'dart:typed_data';

/// Reads the version byte one entry of `Snapshot.data` starts with.
///
/// `Snapshot.schemaVersion` covers the wrapper: the document id, the version
/// vector, and the framing of the entries. Each entry carries a version of its
/// own, so its layout can change on its own.
///
/// A reader states the range it understands rather than a single version, the
/// way a Kafka broker states `min`/`max` per API. That is what lets a newer
/// build read an older blob and migrate it on the way in, instead of refusing
/// the peer that wrote it.
class SnapshotBlob {
  /// Checks the version byte at the head of [bytes] and returns it, together
  /// with the offset of what follows.
  ///
  /// [min] and [max] bound the versions this reader understands; pass the same
  /// value for both when it reads exactly one. [name] names the blob in the
  /// error message.
  ///
  /// Throws a [FormatException] on an empty buffer, and on a version outside
  /// the range. A blob is refused whole rather than read as far as it parses:
  /// half a blob decodes into a state no other peer holds, and says nothing
  /// about it.
  static ({int version, int offset}) read(
    Uint8List bytes, {
    required int min,
    required int max,
    required String name,
  }) {
    if (bytes.isEmpty) {
      throw FormatException('Truncated $name snapshot');
    }

    final version = bytes[0];

    // The two failures are worth telling apart in a log: one asks for a newer
    // build, the other says this build dropped a format it used to read.
    if (version > max) {
      throw FormatException(
        '$name snapshot version $version is newer than this build reads '
        '($min..$max)',
      );
    }
    if (version < min) {
      throw FormatException(
        '$name snapshot version $version is older than this build reads '
        '($min..$max)',
      );
    }

    return (version: version, offset: 1);
  }
}
