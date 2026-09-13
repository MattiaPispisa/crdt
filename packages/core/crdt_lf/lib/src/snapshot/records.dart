import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/snapshot/blob_version.dart';

/// The reserved `Snapshot.data` entries that describe **every** handler at
/// once, rather than holding one handler's state.
///
/// A handler's blob is keyed by its id and stands on its own. These two are
/// keyed by a reserved name and describe the whole document: the manifest says
/// which type each handler id is, the capabilities record says what formats
/// the data is written in. Both matter most once the changes are pruned, when
/// they are the only thing left that remembers.
class SnapshotRecords {
  /// Key of the `{handlerId: handlerType}` manifest used to reconstruct nested
  /// handlers after history pruning.
  ///
  /// The `crdt_lf/` prefix keeps it from colliding with any real handler id.
  static const String manifestKey = 'crdt_lf/handler-manifest';

  /// The version of the manifest blob this build writes and reads.
  static const int manifestVersion = 1;

  /// Key of the record holding what the document's data needs, as
  /// `{handlerType: (kinds, blobVersions)}`.
  ///
  /// Without it a pruned document forgets what its own snapshot contains: the
  /// changes are gone, and the blobs left behind are keyed by handler id, so
  /// nothing ties them back to a handler type. A peer that reloads a compacted
  /// document would then report that it needs nothing at all.
  static const String capabilitiesKey = 'crdt_lf/capabilities';

  /// The version of the capabilities blob this build writes and reads.
  static const int capabilitiesVersion = 1;

  /// The keys that hold document metadata rather than a handler's state, so
  /// nothing reads them as a handler id.
  static const Set<String> reservedKeys = {manifestKey, capabilitiesKey};

  /// Encodes a `{id: type}` manifest as `[u8 version][uvarint count]` followed,
  /// per entry, by `[uvarint idLen][utf8 id][uvarint typeLen][utf8 type]`.
  static Uint8List encodeManifest(Map<String, String> manifest) {
    final out = BytesBuilder(copy: false)..addByte(manifestVersion);
    UVarint.write(manifest.length, out);
    for (final entry in manifest.entries) {
      UVarint.writeString(entry.key, out);
      UVarint.writeString(entry.value, out);
    }
    return out.toBytes();
  }

  /// Decodes a manifest produced by [encodeManifest].
  static Map<String, String> decodeManifest(Uint8List bytes) {
    final manifest = <String, String>{};
    var offset = SnapshotBlob.read(
      bytes,
      min: manifestVersion,
      max: manifestVersion,
      name: 'handler manifest',
    ).offset;
    final countRec = UVarint.read(bytes, offset: offset);
    offset = countRec.nextOffset;
    for (var i = 0; i < countRec.value; i += 1) {
      final idRecord = UVarint.readString(
        bytes,
        offset: offset,
        what: 'handler manifest id',
      );
      offset = idRecord.nextOffset;

      final typeRecord = UVarint.readString(
        bytes,
        offset: offset,
        what: 'handler manifest type',
      );
      offset = typeRecord.nextOffset;

      manifest[idRecord.value] = typeRecord.value;
    }
    return manifest;
  }

  /// Encodes a capabilities record as `[u8 version][uvarint count]` followed,
  /// per entry, by `[uvarint typeLen][utf8 type]`
  /// `[u8 hasBlobRange]` and, when it is `1`, `[uvarint min][uvarint max]`,
  /// then `[uvarint kindCount][u8 kind]...`.
  static Uint8List encodeRequirements(DocumentRequirements requirements) {
    final out = BytesBuilder(copy: false)..addByte(capabilitiesVersion);
    UVarint.write(requirements.byHandlerType.length, out);
    for (final entry in requirements.byHandlerType.entries) {
      UVarint.writeString(entry.key, out);
      final blob = entry.value.blobVersions;
      out.addByte(blob == null ? 0 : 1);
      if (blob != null) {
        UVarint.write(blob.min, out);
        UVarint.write(blob.max, out);
      }
      UVarint.write(entry.value.operationKinds.length, out);
      for (final kind in entry.value.operationKinds.toList()..sort()) {
        out.addByte(kind);
      }
    }
    return out.toBytes();
  }

  /// Decodes a record produced by [encodeRequirements].
  static DocumentRequirements decodeRequirements(Uint8List bytes) {
    final byType = <String, HandlerFormats>{};
    var offset = SnapshotBlob.read(
      bytes,
      min: capabilitiesVersion,
      max: capabilitiesVersion,
      name: 'capabilities',
    ).offset;
    final countRec = UVarint.read(bytes, offset: offset);
    offset = countRec.nextOffset;
    for (var i = 0; i < countRec.value; i += 1) {
      final typeRec = UVarint.readString(
        bytes,
        offset: offset,
        what: 'capabilities handler type',
      );
      offset = typeRec.nextOffset;
      if (offset >= bytes.length) {
        throw const FormatException('Truncated capabilities blob range');
      }
      final hasBlobRange = bytes[offset] == 1;
      offset += 1;
      BlobVersionRange? blob;
      if (hasBlobRange) {
        final minRec = UVarint.read(bytes, offset: offset);
        offset = minRec.nextOffset;
        final maxRec = UVarint.read(bytes, offset: offset);
        offset = maxRec.nextOffset;
        blob = BlobVersionRange(minRec.value, maxRec.value);
      }
      final kindCountRec = UVarint.read(bytes, offset: offset);
      offset = kindCountRec.nextOffset;
      final kinds = <int>{};
      for (var k = 0; k < kindCountRec.value; k += 1) {
        if (offset >= bytes.length) {
          throw const FormatException('Truncated capabilities kinds');
        }
        kinds.add(bytes[offset]);
        offset += 1;
      }
      byType[typeRec.value] = HandlerFormats(
        operationKinds: kinds,
        blobVersions: blob,
      );
    }
    return DocumentRequirements(byType);
  }

  /// `Snapshot.merged`, with the two records above unioned instead of
  /// resolved.
  ///
  /// A merge settles a key by taking one side's value, which is what a
  /// handler's state wants: one blob holds that handler's whole state, so the
  /// newer one replaces the older. These two describe **every** handler at
  /// once, so letting one side win throws away what the other knew.
  ///
  /// It costs a document its memory across a restart: a store-and-forward
  /// server that merges two peers' snapshots would write down half of what it
  /// holds, read it back after a restart, and tell the next peer the document
  /// needs less than it does.
  static Snapshot mergeKeepingRecords(Snapshot a, Snapshot b) {
    final merged = a.merged(b);
    final data = Map<String, Uint8List>.of(merged.data);

    final capabilities = _union(
      a.data[capabilitiesKey],
      b.data[capabilitiesKey],
      decode: decodeRequirements,
      encode: encodeRequirements,
      union: (x, y) => x.merge(y),
    );
    if (capabilities != null) {
      data[capabilitiesKey] = capabilities;
    }

    final manifest = _union(
      a.data[manifestKey],
      b.data[manifestKey],
      decode: decodeManifest,
      encode: encodeManifest,
      // An id names one handler, so both sides agree on its type wherever they
      // overlap; the union is only ever wider.
      union: (x, y) => {...x, ...y},
    );
    if (manifest != null) {
      data[manifestKey] = manifest;
    }

    return Snapshot(
      id: merged.id,
      versionVector: merged.versionVector,
      data: data,
    );
  }
}

/// [a] and [b] decoded, unioned and encoded back, or whichever one is readable
/// when the other is absent or corrupt.
///
/// Returns `null` when neither side has a record to keep. A record that cannot
/// be decoded is dropped rather than thrown on: it is a description of the
/// data, not the data.
Uint8List? _union<T>(
  Uint8List? a,
  Uint8List? b, {
  required T Function(Uint8List) decode,
  required Uint8List Function(T) encode,
  required T Function(T, T) union,
}) {
  T? read(Uint8List? bytes) {
    if (bytes == null) {
      return null;
    }
    try {
      return decode(bytes);
    } catch (_) {
      return null;
    }
  }

  final left = read(a);
  final right = read(b);

  if (left == null) {
    return right == null ? null : encode(right);
  }
  if (right == null) {
    return encode(left);
  }
  return encode(union(left, right));
}
