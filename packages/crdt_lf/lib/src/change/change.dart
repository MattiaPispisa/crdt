import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Change implementation for CRDT.
///
/// A Change represents a modification to the CRDT state.
class Change {
  /// Creates a new [Change] with the given properties.
  factory Change({
    required OperationId id,
    required Operation operation,
    required Set<OperationId> deps,
    required PeerId author,
  }) {
    return Change.fromPayloadBytes(
      id: id,
      deps: deps,
      author: author,
      payloadBytes: operation.toBytes(),
    );
  }

  Change._({
    required this.meta,
    required this.bytes,
  }) {
    if (meta.length != 4) {
      throw ArgumentError.value(meta.length, 'meta.length', 'Must be 4');
    }
    if (meta[_metaSchema] != schemaVersion) {
      throw ArgumentError.value(
        meta[_metaSchema],
        'meta.schema',
        'Unsupported schema version',
      );
    }
    if (meta[_metaDepsCount] < 0) {
      throw ArgumentError.value(meta[_metaDepsCount], 'depsCount');
    }
    if (meta[_metaPayloadOffset] < 0) {
      throw ArgumentError.value(meta[_metaPayloadOffset], 'payloadOffset');
    }
    if (meta[_metaPayloadLength] < 0) {
      throw ArgumentError.value(meta[_metaPayloadLength], 'payloadLength');
    }
    if (meta[_metaPayloadOffset] + meta[_metaPayloadLength] != bytes.length) {
      throw ArgumentError('Invalid payload bounds');
    }
  }

  /// Decodes a [Change] from a self-describing byte buffer produced by
  /// [toBytes].
  ///
  /// Layout:
  /// - `schemaVersion: u8`
  /// - `depsCount: uvarint`
  /// - `id: 24 bytes` ([OperationId])
  /// - `deps: 24 * depsCount bytes`
  /// - `payloadLen: uvarint`
  /// - `payload: payloadLen bytes`
  factory Change.fromBytes(Uint8List data) {
    if (data.isEmpty) {
      throw const FormatException('Truncated Change');
    }
    final version = data[0];
    if (version != schemaVersion) {
      throw FormatException('Unsupported Change schema version: $version');
    }
    var offset = 1;

    final depsCountRec = UVarint.read(data, offset: offset);
    final depsCount = depsCountRec.value;
    offset = depsCountRec.nextOffset;

    if (offset + OperationId.byteLength > data.length) {
      throw const FormatException('Truncated Change id');
    }
    final id = OperationId.fromUint8List(data, offset: offset);
    offset += OperationId.byteLength;

    final deps = <OperationId>{};
    for (var i = 0; i < depsCount; i += 1) {
      if (offset + OperationId.byteLength > data.length) {
        throw const FormatException('Truncated Change deps');
      }
      deps.add(OperationId.fromUint8List(data, offset: offset));
      offset += OperationId.byteLength;
    }

    final payloadLenRec = UVarint.read(data, offset: offset);
    final payloadLen = payloadLenRec.value;
    offset = payloadLenRec.nextOffset;

    final payloadEnd = offset + payloadLen;
    if (payloadEnd > data.length) {
      throw const FormatException('Truncated Change payload');
    }
    final payload = Uint8List.sublistView(data, offset, payloadEnd);

    if (payloadEnd != data.length) {
      throw const FormatException('Trailing bytes after Change');
    }

    return Change.fromPayloadBytes(
      id: id,
      deps: deps,
      author: id.peerId,
      payloadBytes: payload,
    );
  }

  /// Creates a new [Change] with the given properties.
  factory Change.fromPayloadBytes({
    required OperationId id,
    required Set<OperationId> deps,
    required PeerId author,
    required Uint8List payloadBytes,
  }) {
    if (author != id.peerId) {
      throw ArgumentError.value(
        author,
        'author',
        'Author must match operation id peer',
      );
    }

    final depsCount = deps.length;
    final payloadOffset =
        OperationId.byteLength + depsCount * OperationId.byteLength;
    final bytes = Uint8List(payloadOffset + payloadBytes.length)
      ..setRange(0, OperationId.byteLength, id.toUint8List());

    // deps (24 * deps count)
    var cursor = OperationId.byteLength;
    for (final dep in deps) {
      bytes.setRange(
        cursor,
        cursor + OperationId.byteLength,
        dep.toUint8List(),
      );
      cursor += OperationId.byteLength;
    }

    // payload
    bytes.setRange(
      payloadOffset,
      payloadOffset + payloadBytes.length,
      payloadBytes,
    );

    final meta = Int32List(4);
    meta[_metaSchema] = schemaVersion;
    meta[_metaDepsCount] = depsCount;
    meta[_metaPayloadOffset] = payloadOffset;
    meta[_metaPayloadLength] = payloadBytes.length;

    return Change._(
      meta: meta,
      bytes: bytes,
    );
  }

  /// Schema version for the current binary layout.
  static const int schemaVersion = 2;

  /// Metadata layout (indices in [meta]).
  static const int _metaSchema = 0;
  static const int _metaDepsCount = 1;
  static const int _metaPayloadOffset = 2;
  static const int _metaPayloadLength = 3;

  /// The change metadata (ints only).
  final Int32List meta;

  /// The change bytes (payload and ids).
  final Uint8List bytes;

  /// The unique identifier for this change (decoded).
  OperationId get id {
    return OperationId.fromUint8List(
      bytes,
    );
  }

  /// Packed key view for this change id.
  OpIdKey get key {
    return OpIdKey.view(
      bytes,
    );
  }

  /// The peer that created this change
  PeerId get author => PeerId.fromUint8List(
        bytes,
      );

  /// The dependencies of this change (decoded).
  Set<OperationId> get deps {
    final count = meta[_metaDepsCount];
    final result = <OperationId>{};

    var cursor = OperationId.byteLength;
    for (var i = 0; i < count; i += 1) {
      result.add(OperationId.fromUint8List(bytes, offset: cursor));
      cursor += OperationId.byteLength;
    }

    return result;
  }

  /// The number of dependencies stored in this change.
  int get depsCount => meta[_metaDepsCount];

  /// Returns dependency ids as packed keys, without decoding to [OperationId].
  Iterable<OpIdKey> depsKeys() sync* {
    final count = meta[_metaDepsCount];
    var cursor = OperationId.byteLength;
    for (var i = 0; i < count; i += 1) {
      yield OpIdKey.view(bytes, offset: cursor);
      cursor += OperationId.byteLength;
    }
  }

  /// The timestamp when this change was created
  HybridLogicalClock get hlc => HybridLogicalClock.fromUint8List(
        bytes,
        offset: 16,
      );

  /// Encodes this change into a self-describing byte buffer.
  ///
  /// Layout: see [Change.fromBytes].
  Uint8List toBytes() {
    final out = BytesBuilder(copy: false)..addByte(schemaVersion);
    final depsCount = meta[_metaDepsCount];
    UVarint.write(depsCount, out);
    out.add(
      Uint8List.sublistView(bytes, 0, meta[_metaPayloadOffset]),
    );
    final payloadLen = meta[_metaPayloadLength];
    UVarint.write(payloadLen, out);
    out.add(payloadBytes());
    return out.toBytes();
  }

  /// Returns a view of the payload bytes.
  Uint8List payloadBytes() {
    final off = meta[_metaPayloadOffset];
    final len = meta[_metaPayloadLength];
    return Uint8List.sublistView(bytes, off, off + len);
  }

  /// Returns a string representation of this change
  @override
  String toString() {
    final depsStr = deps.map((d) => d.toString()).join(', ');
    return 'Change(id: $id, deps: [$depsStr], '
        'hlc: $hlc, author: $author, payload: ${payloadBytes().length} bytes)';
  }

  /// Compares two Changes for equality
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    if (other is! Change) {
      return false;
    }

    if (other.meta.length != meta.length) {
      return false;
    }
    for (var i = 0; i < meta.length; i += 1) {
      if (other.meta[i] != meta[i]) {
        return false;
      }
    }

    if (other.bytes.length != bytes.length) {
      return false;
    }
    for (var i = 0; i < bytes.length; i += 1) {
      if (other.bytes[i] != bytes[i]) {
        return false;
      }
    }
    return true;
  }

  /// Returns a hash code for this Change
  @override
  int get hashCode {
    var hash = 0x811C9DC5;
    for (var i = 0; i < meta.length; i += 1) {
      hash ^= meta[i];
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    for (var i = 0; i < bytes.length; i += 1) {
      hash ^= bytes[i];
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}

/// Utilities on [List] of [Change]s
extension ChangeList on List<Change> {
  /// Sort changes first by hlc then for author.
  ///
  /// If [inplace] is `true`, the list is sorted in place.
  /// Otherwise, a new list is returned.
  List<Change> sorted({
    bool inplace = false,
  }) {
    if (inplace) {
      sort(_hlcCompare);
      return this;
    }

    return List.from(this)..sort(_hlcCompare);
  }

  int _hlcCompare(Change a, Change b) {
    final hlcCompare = a.hlc.compareTo(b.hlc);
    if (hlcCompare != 0) {
      return hlcCompare;
    }
    return a.author.compareTo(b.author);
  }
}

/// Utilities on [Iterable] of [Change]s
extension ChangeIterable on Iterable<Change> {
  /// {@template change_iterable_newer_than}
  /// Returns the changes that are newer than the given [versionVector].
  ///
  /// A change is considered newer if its clock is strictly greater than the
  /// clock in the provided version vector for the same peer, or if the peer is
  /// not present in the provided vector.
  /// {@endtemplate}
  Iterable<Change> newerThan(VersionVector versionVector) {
    return where((change) {
      final hlc = versionVector[change.id.peerId];
      if (hlc == null) {
        return true;
      }
      return change.hlc.compareTo(hlc) > 0;
    });
  }
}
