import 'package:crdt_lf/crdt_lf.dart';

/// The range of snapshot blob layouts a peer reads, or a document holds.
///
/// A build reads every layout from [min] to [max], and writes [max].
class BlobVersionRange {
  /// Creates the range `min..max`.
  const BlobVersionRange(this.min, this.max);

  /// The range of a build, or of data, that knows exactly one [version].
  const BlobVersionRange.single(int version)
      : min = version,
        max = version;

  /// The oldest layout, inclusive.
  final int min;

  /// The newest layout, inclusive.
  final int max;

  /// The narrowest range holding both this and [other]. Only widens.
  BlobVersionRange merge(BlobVersionRange other) => BlobVersionRange(
        min < other.min ? min : other.min,
        max > other.max ? max : other.max,
      );

  @override
  bool operator ==(Object other) =>
      other is BlobVersionRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => min == max ? 'v$min' : 'v$min..v$max';
}

/// The format of a handler.
///
/// What they stand for depends on what holds them: the formats a peer reads
/// in a [DocumentCapabilities], the formats a document holds in a
/// [DocumentRequirements].
class HandlerFormats {
  /// Creates formats holding [operationKinds] and, when it is known,
  /// [blobVersions].
  const HandlerFormats({
    required this.operationKinds,
    this.blobVersions,
  });

  /// What [handler] reads, derived from the handler itself.
  ///
  /// What a [HandlerSpec] carries is a claim; this is what the handler does.
  /// The document compares the two as a handler registers, and a handler of
  /// your own can be checked the same way.
  factory HandlerFormats.of(Handler<dynamic> handler) => HandlerFormats(
        operationKinds: handler.operationDecoders.keys.toSet(),
        blobVersions: BlobVersionRange(
          handler.minReadableSnapshotBlobVersion,
          handler.snapshotBlobVersion,
        ),
      );

  /// The operation kinds, as in `OperationEnvelope.kind`.
  ///
  /// A kind belongs to the handler kind it is keyed by: the same byte means
  /// different things under two of them.
  final Set<int> operationKinds;

  /// The snapshot blob layouts involved.
  ///
  /// `null` for a kind known from change envelopes alone: an envelope carries
  /// no snapshot version.
  final BlobVersionRange? blobVersions;

  /// Both sets of this and [other], together, and the range that covers both.
  HandlerFormats merge(HandlerFormats other) {
    final mine = blobVersions;
    final theirs = other.blobVersions;

    return HandlerFormats(
      operationKinds: {...operationKinds, ...other.operationKinds},
      blobVersions:
          mine == null ? theirs : (theirs == null ? mine : mine.merge(theirs)),
    );
  }

  /// Merges [formats] into [target] under [handlerType]. Mutates [target].
  static void mergeInto(
    Map<String, HandlerFormats> target,
    String handlerType,
    HandlerFormats formats,
  ) {
    final mine = target[handlerType];
    target[handlerType] = mine == null ? formats : mine.merge(formats);
  }

  HandlerFormats _frozen() {
    return HandlerFormats(
      operationKinds: Set<int>.unmodifiable(operationKinds),
      blobVersions: blobVersions,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HandlerFormats &&
      other.blobVersions == blobVersions &&
      other.operationKinds.length == operationKinds.length &&
      other.operationKinds.containsAll(operationKinds);

  @override
  int get hashCode =>
      Object.hash(blobVersions, Object.hashAllUnordered(operationKinds));

  @override
  String toString() {
    final kinds = operationKinds.toList()..sort();
    return 'HandlerFormats(kinds: $kinds, blob: $blobVersions)';
  }
}

/// An unmodifiable `handlerType` to [HandlerFormats] map.
abstract class _FormatsByHandlerType {
  _FormatsByHandlerType(Map<String, HandlerFormats> byHandlerType)
      : byHandlerType = Map.unmodifiable({
          for (final entry in byHandlerType.entries)
            entry.key: entry.value._frozen(),
        });

  /// The formats, keyed by [Handler.handlerType].
  ///
  /// The key is the type tag that travels in an operation envelope, not the
  /// Dart class name and not the id a handler was opened under.
  final Map<String, HandlerFormats> byHandlerType;

  /// The formats for [handlerType], or `null` when this says nothing about it.
  HandlerFormats? operator [](String handlerType) => byHandlerType[handlerType];

  /// The handler types this covers.
  Iterable<String> get handlerTypes => byHandlerType.keys;

  /// Whether this says nothing at all.
  bool get isEmpty => byHandlerType.isEmpty;

  /// Equal when both sides are the **same** subclass and hold the same map.
  ///
  /// The subclass is part of it: capabilities and requirements answer different
  /// questions, so one never equals the other however alike their maps look.
  ///
  /// Compared where a description travels: `crdt_socket_sync` round-trips one
  /// through JSON in a handshake and checks it came back whole.
  @override
  bool operator ==(Object other) =>
      other is _FormatsByHandlerType &&
      other.runtimeType == runtimeType &&
      other.byHandlerType.length == byHandlerType.length &&
      other.byHandlerType.entries
          .every((entry) => byHandlerType[entry.key] == entry.value);

  @override
  int get hashCode => Object.hashAllUnordered(
        byHandlerType.entries.map((e) => Object.hash(e.key, e.value)),
      );

  /// [byHandlerType] unioned with [other]'s, per handler type.
  Map<String, HandlerFormats> _mergedMap(_FormatsByHandlerType other) {
    final merged = <String, HandlerFormats>{...byHandlerType};
    for (final entry in other.byHandlerType.entries) {
      HandlerFormats.mergeInto(merged, entry.key, entry.value);
    }
    return merged;
  }
}

/// What a peer **can read**, by handler kind.
///
/// Read one with [CRDTDocument.describeBuildCapabilities]. A kind it does not
/// name is one this peer was not set up for, not one it cannot read.
///
/// ```dart
/// final reads = document.describeBuildCapabilities();
/// final needed = document.describeDataRequirements();
///
/// final missing = <String>[
///   for (final kind in needed.handlerTypes)
///     if (reads[kind] == null) kind,
/// ];
/// ```
class DocumentCapabilities extends _FormatsByHandlerType {
  /// Creates capabilities from [byHandlerType].
  DocumentCapabilities(super.byHandlerType);

  @override
  String toString() => 'DocumentCapabilities($byHandlerType)';
}

/// The formats a document's data is written in, by handler kind.
///
/// Read one with [CRDTDocument.describeDataRequirements], and compare it with a
/// [DocumentCapabilities] to find the kinds a peer cannot read.
///
/// A document can require more than it reads: a change written by a peer that
/// knows more is stored and forwarded whole, and reading that handler then
/// throws [UnknownOperationKindException].
class DocumentRequirements extends _FormatsByHandlerType {
  /// Creates requirements from [byHandlerType].
  DocumentRequirements(super.byHandlerType);

  /// Every kind either side names, with the formats of both. Only adds.
  ///
  /// A snapshot drops a blob version instead, so read
  /// [CRDTDocument.describeDataRequirements] again rather than folding across a
  /// [CRDTDocument.takeSnapshot].
  DocumentRequirements merge(DocumentRequirements other) =>
      DocumentRequirements(_mergedMap(other));

  @override
  String toString() => 'DocumentRequirements($byHandlerType)';
}
