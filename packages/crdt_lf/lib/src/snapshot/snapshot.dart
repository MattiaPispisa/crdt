import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crypto/crypto.dart';

/// Represents a snapshot of a CRDTDocument's state at a specific version.
class Snapshot {
  /// Creates a [Snapshot]
  Snapshot({
    required this.id,
    required this.versionVector,
    required Map<String, dynamic> data,
  }) : data = Map.unmodifiable(data);

  /// Converts a JSON object to a [Snapshot]
  factory Snapshot.fromJson(Map<String, dynamic> json) => Snapshot(
        id: json['id'] as String,
        data: Map<String, dynamic>.from(json['data'] as Map),
        versionVector: VersionVector.fromJson(
          json['versionVector'] as Map<String, dynamic>,
        ),
      );

  /// Decodes a [Snapshot] from a binary buffer produced by [toBytes].
  ///
  /// Layout:
  /// - `idLen: uvarint`
  /// - `id: utf8 bytes`
  /// - `vectorLen: uvarint`
  /// - `vector: VersionVector bytes`
  /// - `dataLen: uvarint`
  /// - `data: JsonValueCodec bytes`
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

    final dataLenRec = UVarint.read(bytes, offset: offset);
    offset = dataLenRec.nextOffset;
    final dataEnd = offset + dataLenRec.value;
    if (dataEnd > bytes.length) {
      throw const FormatException('Truncated Snapshot data');
    }
    final data = const JsonValueCodec<Map<String, dynamic>>().decode(
      Uint8List.sublistView(bytes, offset, dataEnd),
    );

    return Snapshot(
      id: id,
      versionVector: versionVector,
      data: data,
    );
  }

  /// Creates a [Snapshot] from a [versionVector].
  factory Snapshot.create({
    required VersionVector versionVector,
    required Map<String, dynamic> data,
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

  /// The actual data representing the snapshot state.
  final Map<String, dynamic> data;

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

  /// Converts the [Snapshot] to a JSON object
  Map<String, dynamic> toJson() => {
        'id': id,
        'data': data,
        'versionVector': versionVector.toJson(),
      };

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

    final dataBytes = const JsonValueCodec<Map<String, dynamic>>().encode(data);
    UVarint.write(dataBytes.length, out);
    out.add(dataBytes);

    return out.toBytes();
  }

  @override
  String toString() {
    return 'Snapshot(id: $id, versionVector: $versionVector, data: $data)';
  }

  /// Generates a stable SHA-256 hash ID from the version set.
  static String _generateIdFromVersion(VersionVector version) {
    if (version.isEmpty) {
      // Define a specific ID for the empty version state
      // Hashing an empty string or using a constant are options.
      return sha256.convert(utf8.encode('')).toString();
    }
    // 1. Convert OperationIds to stable strings
    final versionStrings =
        version.entries.map((entry) => '${entry.key}:${entry.value}').toList()
          // 2. Sort the strings for stability
          ..sort();

    // 3. Concatenate into a single string
    final concatenatedString = versionStrings.join();

    // 4. Hash the concatenated string using SHA-256
    final bytes = utf8.encode(concatenatedString);
    final digest = sha256.convert(bytes);

    // Return the hexadecimal representation of the hash
    return digest.toString();
  }
}
