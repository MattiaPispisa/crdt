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
  })  : assert(meta.length == 4, 'meta must have 4 entries'),
        assert(
          meta[_metaSchema] == schemaVersion,
          'unsupported meta schema version',
        ),
        assert(meta[_metaDepsCount] >= 0, 'depsCount must be non-negative'),
        assert(
          meta[_metaPayloadOffset] >= 0,
          'payloadOffset must be non-negative',
        ),
        assert(
          meta[_metaPayloadLength] >= 0,
          'payloadLength must be non-negative',
        ),
        assert(
          meta[_metaPayloadOffset] + meta[_metaPayloadLength] == bytes.length,
          'payload bounds must match bytes length',
        );

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

    final depsCountRec = UVarint.read(data, offset: 1);
    final depsCount = depsCountRec.value;
    final idDepsStart = depsCountRec.nextOffset;

    // id + deps occupy (1 + depsCount) * 24 contiguous bytes — the same
    // layout used by the internal [bytes] field, so we can slice without
    // round-tripping through OperationId objects.
    if (idDepsStart + OperationId.byteLength > data.length) {
      throw const FormatException('Truncated Change id');
    }
    final idDepsLen = (1 + depsCount) * OperationId.byteLength;
    final idDepsEnd = idDepsStart + idDepsLen;
    if (idDepsEnd > data.length) {
      throw const FormatException('Truncated Change deps');
    }

    final payloadLenRec = UVarint.read(data, offset: idDepsEnd);
    final payloadLen = payloadLenRec.value;
    final payloadStart = payloadLenRec.nextOffset;
    final payloadEnd = payloadStart + payloadLen;
    if (payloadEnd > data.length) {
      throw const FormatException('Truncated Change payload');
    }
    if (payloadEnd != data.length) {
      throw const FormatException('Trailing bytes after Change');
    }

    final bytes = Uint8List(idDepsLen + payloadLen)
      ..setRange(0, idDepsLen, data, idDepsStart)
      ..setRange(idDepsLen, idDepsLen + payloadLen, data, payloadStart);

    final meta = Int32List(4);
    meta[_metaSchema] = schemaVersion;
    meta[_metaDepsCount] = depsCount;
    meta[_metaPayloadOffset] = idDepsLen;
    meta[_metaPayloadLength] = payloadLen;

    return Change._(meta: meta, bytes: bytes);
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

  // Decoded fields are cached lazily to avoid re-parsing on every access.
  late final OperationId _id = OperationId.fromUint8List(bytes);
  late final PeerId _author = PeerId.fromUint8List(bytes);
  late final HybridLogicalClock _hlc =
      HybridLogicalClock.fromUint8List(bytes, offset: 16);
  late final Set<OperationId> _deps = _parseDeps();
  late final OpIdKey _key = OpIdKey.view(bytes);

  Set<OperationId> _parseDeps() {
    final count = meta[_metaDepsCount];
    final result = <OperationId>{};
    var cursor = OperationId.byteLength;
    for (var i = 0; i < count; i += 1) {
      result.add(OperationId.fromUint8List(bytes, offset: cursor));
      cursor += OperationId.byteLength;
    }
    return result;
  }

  /// The unique identifier for this change (decoded).
  OperationId get id => _id;

  /// Packed key view for this change id.
  OpIdKey get key => _key;

  /// The peer that created this change.
  PeerId get author => _author;

  /// The dependencies of this change (decoded).
  Set<OperationId> get deps => _deps;

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

  /// The timestamp when this change was created.
  HybridLogicalClock get hlc => _hlc;

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

  late final int _hashCode = _computeHashCode();

  int _computeHashCode() {
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

  /// Returns a hash code for this Change.
  @override
  int get hashCode => _hashCode;
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
