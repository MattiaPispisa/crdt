part of 'document.dart';

// Everything about capabilities that is not a member of [CRDTDocument]: the
// two value types, the record a snapshot carries, and the probe.
//
// The rest — [CRDTDocument.describeBuildCapabilities],
// [CRDTDocument.describeDataCapabilities] and the state they fold into — stays
// in `document.dart`. Dart has no partial classes, so a class body lives in
// one file whether or not the feature does.

/// Freezes a `handlerType -> capability` map and the sets inside it.
///
/// One place, so a description handed out by [CRDTDocument] and one rebuilt
/// from the wire are equally read-only.
Map<String, HandlerCapability> _freeze(Map<String, HandlerCapability> byType) {
  return Map.unmodifiable({
    for (final entry in byType.entries) entry.key: entry.value._frozen(),
  });
}

/// What a build can do with one handler type.
///
/// The two questions a peer has to answer about a handler type before it can
/// trust the other side: which operations it decodes, and which snapshot blob
/// it reads.
class HandlerCapability {
  /// Constructor
  const HandlerCapability({
    required this.operationKinds,
    this.snapshotBlobVersion,
  });

  /// The operation kinds that can be decoded, as declared by
  /// [Handler.decodableKinds].
  ///
  /// A kind is scoped to the handler type that owns it, so this set only means
  /// anything next to the type it is keyed by.
  final Set<int> operationKinds;

  /// The snapshot blob version, or `null` when it is not known.
  ///
  /// Set whenever the capability describes a **build** ([Handler
  /// .snapshotBlobVersion]). `null` when it describes **data** whose blob
  /// version was never recorded: the operation kinds were read back from
  /// change envelopes, and an envelope says nothing about snapshots.
  final int? snapshotBlobVersion;

  /// The union of this capability and [other].
  ///
  /// Kinds add up. The blob version is a single number per build, so the first
  /// one that is known wins; two different ones cannot both be right, and the
  /// disagreement belongs to whoever built the map.
  HandlerCapability merge(HandlerCapability other) {
    return HandlerCapability(
      operationKinds: {...operationKinds, ...other.operationKinds},
      snapshotBlobVersion: snapshotBlobVersion ?? other.snapshotBlobVersion,
    );
  }

  HandlerCapability _frozen() {
    return HandlerCapability(
      operationKinds: Set<int>.unmodifiable(operationKinds),
      snapshotBlobVersion: snapshotBlobVersion,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HandlerCapability &&
      other.snapshotBlobVersion == snapshotBlobVersion &&
      other.operationKinds.length == operationKinds.length &&
      other.operationKinds.containsAll(operationKinds);

  @override
  int get hashCode => Object.hash(
        snapshotBlobVersion,
        Object.hashAllUnordered(operationKinds),
      );

  @override
  String toString() {
    final kinds = operationKinds.toList()..sort();
    return 'HandlerCapability(kinds: $kinds, '
        'snapshotBlobVersion: $snapshotBlobVersion)';
  }
}

/// What a peer can read, or what a document's data holds, by handler type.
///
/// Two documents answer two different questions with this same shape, and the
/// pair is what makes a compatibility check possible:
/// [CRDTDocument.describeBuildCapabilities] says what this **build** decodes,
/// [CRDTDocument.describeDataCapabilities] says what the **data** contains.
class DocumentCapabilities {
  /// Creates a description from an explicit map.
  ///
  /// The map and the sets inside it are copied and frozen, so a caller cannot
  /// change a description after handing it over.
  DocumentCapabilities(Map<String, HandlerCapability> byHandlerType)
      : byHandlerType = _freeze(byHandlerType);

  /// A description that claims nothing.
  DocumentCapabilities.empty() : byHandlerType = const {};

  /// The capabilities, keyed by [Handler.handlerType].
  ///
  /// The key is the type tag that travels in an operation envelope, not the
  /// Dart class name and not the id a handler was opened under.
  final Map<String, HandlerCapability> byHandlerType;

  /// The capability declared for [handlerType], or `null` when this
  /// description says nothing about it.
  HandlerCapability? operator [](String handlerType) =>
      byHandlerType[handlerType];

  /// The handler types this description covers.
  Iterable<String> get handlerTypes => byHandlerType.keys;

  /// Whether this description claims nothing at all.
  bool get isEmpty => byHandlerType.isEmpty;

  /// Whether this description claims anything.
  bool get isNotEmpty => byHandlerType.isNotEmpty;

  /// The union of this description and [other], per handler type.
  ///
  /// Grows only, which is what lets a description be folded together from
  /// several sources (open handlers, registered factories, a snapshot record)
  /// without any of them being able to take a claim away.
  DocumentCapabilities merge(DocumentCapabilities other) {
    final merged = <String, HandlerCapability>{...byHandlerType};
    for (final entry in other.byHandlerType.entries) {
      final mine = merged[entry.key];
      merged[entry.key] =
          mine == null ? entry.value : mine.merge(entry.value);
    }
    return DocumentCapabilities(merged);
  }

  @override
  bool operator ==(Object other) =>
      other is DocumentCapabilities &&
      other.byHandlerType.length == byHandlerType.length &&
      other.byHandlerType.entries
          .every((entry) => byHandlerType[entry.key] == entry.value);

  @override
  int get hashCode => Object.hashAllUnordered(
        byHandlerType.entries.map((e) => Object.hash(e.key, e.value)),
      );

  @override
  String toString() => 'DocumentCapabilities($byHandlerType)';
}

/// The id handed to a factory when it is called only to read what its handler
/// decodes. It lives on a throwaway document, so it never collides with a real
/// handler id.
const String _probeHandlerId = 'crdt_lf/capability-probe';

/// What [handler] says it can read.
HandlerCapability _capabilityOf(Handler<dynamic> handler) {
  return HandlerCapability(
    operationKinds: handler.decodableKinds,
    snapshotBlobVersion: handler.snapshotBlobVersion,
  );
}

/// Reserved [Snapshot] data key holding what the document's data needs, as
/// `{handlerType: (kinds, snapshotBlobVersion)}`.
///
/// Without it a pruned document forgets what its own snapshot contains: the
/// changes are gone, and the blobs left behind are keyed by handler id, so
/// nothing ties them back to a handler type. A peer that reloads a compacted
/// document would then report that it needs nothing at all.
const String _capabilitiesKey = 'crdt_lf/capabilities';

/// The version of the capabilities blob this build writes and reads.
const int _capabilitiesVersion = 1;

/// The blob version written for a type this build knows only from its changes.
///
/// Zero is not a legal [Handler.snapshotBlobVersion] for a blob written by
/// this build, so it is free to mean "not known".
const int _unknownBlobVersion = 0;

/// Encodes a capabilities record as `[u8 version][uvarint count]` followed,
/// per entry, by `[uvarint typeLen][utf8 type][uvarint blobVersion]`
/// `[uvarint kindCount][u8 kind]...`.
Uint8List _encodeCapabilities(DocumentCapabilities capabilities) {
  final out = BytesBuilder(copy: false)..addByte(_capabilitiesVersion);
  UVarint.write(capabilities.byHandlerType.length, out);
  for (final entry in capabilities.byHandlerType.entries) {
    UVarint.writeString(entry.key, out);
    UVarint.write(entry.value.snapshotBlobVersion ?? _unknownBlobVersion, out);
    UVarint.write(entry.value.operationKinds.length, out);
    for (final kind in entry.value.operationKinds.toList()..sort()) {
      out.addByte(kind);
    }
  }
  return out.toBytes();
}

/// Decodes a record produced by [_encodeCapabilities].
DocumentCapabilities _decodeCapabilities(Uint8List bytes) {
  final byType = <String, HandlerCapability>{};
  var offset = SnapshotBlob.read(
    bytes,
    version: _capabilitiesVersion,
    name: 'capabilities',
  );
  final countRec = UVarint.read(bytes, offset: offset);
  offset = countRec.nextOffset;
  for (var i = 0; i < countRec.value; i += 1) {
    final typeRec = UVarint.readString(
      bytes,
      offset: offset,
      what: 'capabilities handler type',
    );
    offset = typeRec.nextOffset;
    final blobRec = UVarint.read(bytes, offset: offset);
    offset = blobRec.nextOffset;
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
    byType[typeRec.value] = HandlerCapability(
      operationKinds: kinds,
      snapshotBlobVersion:
          blobRec.value == _unknownBlobVersion ? null : blobRec.value,
    );
  }
  return DocumentCapabilities(byType);
}
