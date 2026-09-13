import 'package:crdt_lf/crdt_lf.dart';

/// The range of snapshot blob layouts a peer reads, or a document holds.
///
/// A build reads every layout from [min] to [max] and writes [max]. A range
/// rather than a set is what makes the comparison two integer checks, and what
/// lets a newer build accept an older blob and migrate it on the way in — see
/// [Handler.minReadableSnapshotBlobVersion].
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

  /// The narrowest range holding both this and [other].
  ///
  /// Widens, so folding several sources cannot exclude a layout one of them
  /// named.
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

/// The operation kinds and snapshot blob versions of one handler type.
///
/// What they stand for depends on what holds them: the formats a peer reads
/// in a [DocumentCapabilities], the formats a document holds in a
/// [DocumentRequirements].
///
/// {@template handler_formats_constant}
/// Each built-in handler holds one as a private constant, for the places that
/// have no instance to read: `snapshotBlobVersion` derives from it and its
/// [HandlerSpec] carries it, which is the only way out —
/// `CRDTListHandler.spec<Todo>('todos').formats`.
/// [HandlerSpec.create] checks it against a handler it builds.
/// {@endtemplate}
class HandlerFormats {
  /// Creates formats holding [operationKinds] and, when it is known,
  /// [blobVersions].
  const HandlerFormats({
    required this.operationKinds,
    this.blobVersions,
  });

  /// The operation kinds, as in `OperationEnvelope.kind`.
  ///
  /// A kind belongs to the handler type it is keyed by, so the same value
  /// means different things under two types.
  final Set<int> operationKinds;

  /// The snapshot blob layouts involved; `null` when none is known.
  ///
  /// For a build it is what it reads,
  /// `minReadableSnapshotBlobVersion..snapshotBlobVersion`. For a document it
  /// is what its blobs are written with, widened to cover them all when
  /// snapshots from peers on different builds were merged.
  ///
  /// `null` for a type known from change envelopes alone: an envelope carries
  /// no snapshot version.
  final BlobVersionRange? blobVersions;

  /// Both sets of this and [other], together.
  ///
  /// Two blob versions do not resolve to one: a document that holds both keeps
  /// both.
  HandlerFormats merge(HandlerFormats other) {
    final mine = blobVersions;
    final theirs = other.blobVersions;

    return HandlerFormats(
      operationKinds: {...operationKinds, ...other.operationKinds},
      blobVersions:
          mine == null ? theirs : (theirs == null ? mine : mine.merge(theirs)),
    );
  }

  /// Merges [formats] into [target] under [handlerType].
  ///
  /// Mutates [target]. An entry already there becomes [merge] of the two, so a
  /// type named by two sources keeps what each of them knew.
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

  /// [byHandlerType] unioned with [other]'s, per handler type.
  Map<String, HandlerFormats> _mergedMap(_FormatsByHandlerType other) {
    final merged = <String, HandlerFormats>{...byHandlerType};
    for (final entry in other.byHandlerType.entries) {
      HandlerFormats.mergeInto(merged, entry.key, entry.value);
    }
    return merged;
  }

  /// Equal when both sides are the **same** subclass and hold the same map.
  ///
  /// The subclass is part of it: capabilities and requirements answer
  /// different questions, so one never equals the other however alike their
  /// maps look.
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
}

/// What a peer **can read**.
///
/// Covers the handlers a document has opened and the types its registered
/// factories can build. A handler decodes through the value codec its instance
/// holds, so a type nothing has wired up is absent even when this package
/// ships the class.
///
/// Read one with [CRDTDocument.describeBuildCapabilities]. Compare it with the
/// [DocumentRequirements] of a document to find the types this peer cannot
/// read:
///
/// ```dart
/// final reads = document.describeBuildCapabilities();
/// final needed = document.describeDataRequirements();
///
/// final missing = <String>[
///   for (final type in needed.handlerTypes)
///     if (reads[type] == null) type,
/// ];
/// ```
class DocumentCapabilities extends _FormatsByHandlerType {
  /// Creates capabilities from [byHandlerType].
  DocumentCapabilities(super.byHandlerType);

  /// Every type either side names, with the formats of both.
  ///
  /// Only adds, so folding several sources together cannot drop a type or a
  /// kind one of them named.
  DocumentCapabilities merge(DocumentCapabilities other) =>
      DocumentCapabilities(_mergedMap(other));

  @override
  String toString() => 'DocumentCapabilities($byHandlerType)';
}

/// The formats a document's data is written in, by handler type.
///
/// A peer that cannot decode one of them cannot read that part of the
/// document; compare with a [DocumentCapabilities] to find out which.
///
/// Read from the changes and the snapshot rather than from the handlers, so a
/// document that has opened none still answers in full. Use
/// [CRDTDocument.describeDataRequirements].
///
/// A document can require more than it reads: applying a change never decodes
/// its operation, so one written by a peer that knows more is stored and
/// forwarded whole. Reading that handler then throws
/// [UnknownOperationKindException].
class DocumentRequirements extends _FormatsByHandlerType {
  /// Creates requirements from [byHandlerType].
  DocumentRequirements(super.byHandlerType);

  /// Every type either side names, with the formats of both.
  ///
  /// Only adds. A document drops a blob version instead when it snapshots, so
  /// use [CRDTDocument.describeDataRequirements] rather than folding by hand
  /// across a [CRDTDocument.takeSnapshot].
  DocumentRequirements merge(DocumentRequirements other) =>
      DocumentRequirements(_mergedMap(other));

  @override
  String toString() => 'DocumentRequirements($byHandlerType)';
}
