import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crypto/crypto.dart';

/// Represents a snapshot of a CRDTDocument's state at a specific version.
///
/// Each entry in [data] is the opaque binary representation of one consumer's
/// (handler's) projected state. The handler is responsible for encoding and
/// decoding its own state — `crdt_lf` only treats each entry as a `Uint8List`.
class Snapshot {
  /// Creates a [Snapshot].
  Snapshot({
    required this.id,
    required this.versionVector,
    required Map<String, Uint8List> data,
  }) : data = Map.unmodifiable(data);

  /// Decodes a [Snapshot] from a binary buffer produced by [toBytes].
  ///
  /// Layout:
  /// - `idLen: uvarint`
  /// - `id: utf8 bytes`
  /// - `vectorLen: uvarint`
  /// - `vector: VersionVector bytes`
  /// - `entryCount: uvarint`
  /// - repeated `entryCount` times:
  ///   - `keyLen: uvarint`
  ///   - `key: utf8 bytes`
  ///   - `valueLen: uvarint`
  ///   - `value: bytes` (opaque, owned by the consumer that produced it)
  factory Snapshot.fromBytes(Uint8List bytes) {
    var offset = 0;

    final idLenRec = UVarint.read(bytes, offset: offset);
    offset = idLenRec.nextOffset;
    final idEnd = offset + idLenRec.value;
    if (idEnd > bytes.length) {
      throw const FormatException('Truncated Snapshot id');
    }
    final id = utf8.decode(Uint8List.sublistView(bytes, offset, idEnd));
    offset = idEnd;

    final vvLenRec = UVarint.read(bytes, offset: offset);
    offset = vvLenRec.nextOffset;
    final vvEnd = offset + vvLenRec.value;
    if (vvEnd > bytes.length) {
      throw const FormatException('Truncated Snapshot versionVector');
    }
    final versionVector = VersionVector.fromBytes(
      Uint8List.sublistView(bytes, offset, vvEnd),
    );
    offset = vvEnd;

    final countRec = UVarint.read(bytes, offset: offset);
    offset = countRec.nextOffset;
    final data = <String, Uint8List>{};
    for (var i = 0; i < countRec.value; i += 1) {
      final keyLenRec = UVarint.read(bytes, offset: offset);
      offset = keyLenRec.nextOffset;
      final keyEnd = offset + keyLenRec.value;
      if (keyEnd > bytes.length) {
        throw const FormatException('Truncated Snapshot data key');
      }
      final key = utf8.decode(Uint8List.sublistView(bytes, offset, keyEnd));
      offset = keyEnd;

      final valueLenRec = UVarint.read(bytes, offset: offset);
      offset = valueLenRec.nextOffset;
      final valueEnd = offset + valueLenRec.value;
      if (valueEnd > bytes.length) {
        throw const FormatException('Truncated Snapshot data value');
      }
      data[key] = Uint8List.fromList(
        Uint8List.sublistView(bytes, offset, valueEnd),
      );
      offset = valueEnd;
    }

    return Snapshot(
      id: id,
      versionVector: versionVector,
      data: data,
    );
  }

  /// Creates a [Snapshot] from a [versionVector].
  factory Snapshot.create({
    required VersionVector versionVector,
    required Map<String, Uint8List> data,
  }) {
    return Snapshot(
      id: _generateIdFromVersion(versionVector),
      versionVector: versionVector,
      data: data,
    );
  }

  /// A stable identifier derived from the version.
  final String id;

  /// The version vector of the snapshot.
  final VersionVector versionVector;

  /// The actual data representing the snapshot state, keyed by handler id.
  ///
  /// Each value is the opaque binary blob the corresponding handler produced
  /// via its `getSnapshotState()`.
  final Map<String, Uint8List> data;

  /// Merges two [Snapshot]s.
  ///
  /// [Snapshot.data] is merged based on the [versionVector]. The newer snapshot
  /// will overwrite the data of the older snapshot.
  Snapshot merged(Snapshot other) {
    var data = this.data;
    if (other.versionVector.isStrictlyNewerOrEqualThan(this.versionVector)) {
      data = {...data, ...other.data};
    } else {
      data = {...other.data, ...data};
    }
    final versionVector = this.versionVector.merged(other.versionVector);

    return Snapshot(
      id: _generateIdFromVersion(versionVector),
      versionVector: versionVector,
      data: data,
    );
  }

  /// Encodes this snapshot to a compact binary representation.
  ///
  /// See [Snapshot.fromBytes] for the layout.
  Uint8List toBytes() {
    final out = BytesBuilder(copy: false);

    final idBytes = utf8.encode(id);
    UVarint.write(idBytes.length, out);
    out.add(idBytes);

    final vvBytes = versionVector.toBytes();
    UVarint.write(vvBytes.length, out);
    out.add(vvBytes);

    UVarint.write(data.length, out);
    for (final entry in data.entries) {
      final keyBytes = utf8.encode(entry.key);
      UVarint.write(keyBytes.length, out);
      out.add(keyBytes);

      UVarint.write(entry.value.length, out);
      out.add(entry.value);
    }

    return out.toBytes();
  }

  @override
  String toString() {
    return 'Snapshot(id: $id, versionVector: $versionVector, '
        'data: ${data.length} entries)';
  }

  /// Generates a stable SHA-256 hash ID from the version set.
  static String _generateIdFromVersion(VersionVector version) {
    if (version.isEmpty) {
      return sha256.convert(utf8.encode('')).toString();
    }
    final versionStrings = version.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .toList()
      ..sort();

    final concatenatedString = versionStrings.join();
    final bytes = utf8.encode(concatenatedString);
    final digest = sha256.convert(bytes);

    return digest.toString();
  }
}
