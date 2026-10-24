// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crypto/crypto.dart';

/// Represents a snapshot of a CRDTDocument's state at a specific version.
///
/// Most entries in [data] are the opaque binary state of one handler, keyed
/// by its id: the handler is responsible for encoding and decoding it,
/// `crdt_lf` only treats the entry as a `Uint8List`. A handful of entries,
/// keyed by a reserved `crdt_lf/`-prefixed name instead of a handler id,
/// describe the document as a whole — see [CRDTDocument.takeSnapshot].
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
  /// - `schemaVersion: u8`
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
  ///
  /// [schemaVersion] covers the wrapper only — the id, the version vector and
  /// the framing of the entries. Each entry value carries its own version,
  /// written and read by the handler that owns it.
  factory Snapshot.fromBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('Truncated Snapshot');
    }
    final version = bytes[0];
    if (version != schemaVersion) {
      throw FormatException(
        'Unsupported Snapshot schema version: $version '
        '(this build reads $schemaVersion)',
      );
    }
    var offset = 1;

    final idRecord = UVarint.readString(
      bytes,
      offset: offset,
      what: 'Snapshot id',
    );
    final id = idRecord.value;
    offset = idRecord.nextOffset;

    final vvRecord = UVarint.readBytes(
      bytes,
      offset: offset,
      what: 'Snapshot versionVector',
    );
    final versionVector = VersionVector.fromBytes(vvRecord.value);
    offset = vvRecord.nextOffset;

    final countRec = UVarint.read(bytes, offset: offset);
    offset = countRec.nextOffset;
    final data = <String, Uint8List>{};
    for (var i = 0; i < countRec.value; i += 1) {
      final keyRecord = UVarint.readString(
        bytes,
        offset: offset,
        what: 'Snapshot data key',
      );
      offset = keyRecord.nextOffset;

      final valueRecord = UVarint.readBytes(
        bytes,
        offset: offset,
        what: 'Snapshot data value',
      );
      data[keyRecord.value] = Uint8List.fromList(valueRecord.value);
      offset = valueRecord.nextOffset;
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

  /// Schema version for the current binary layout.
  static const int schemaVersion = 1;

  /// A stable identifier derived from the version.
  final String id;

  /// The version vector of the snapshot.
  final VersionVector versionVector;

  /// The snapshot state.
  ///
  /// Most entries are keyed by a handler id, and their value is the opaque
  /// binary blob that handler produced via its `getSnapshotState()`. A
  /// handful of reserved entries, keyed by a `crdt_lf/`-prefixed name instead
  /// of a handler id, describe the document as a whole: see
  /// [CRDTDocument.takeSnapshot].
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
    final out = BytesBuilder(copy: false)..addByte(schemaVersion);

    UVarint.writeString(id, out);
    UVarint.writeBytes(versionVector.toBytes(), out);

    UVarint.write(data.length, out);
    for (final entry in data.entries) {
      UVarint.writeString(entry.key, out);
      UVarint.writeBytes(entry.value, out);
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
