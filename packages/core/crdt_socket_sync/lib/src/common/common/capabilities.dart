import 'package:crdt_lf/crdt_lf.dart';

/// One reason a build cannot handle what another peer holds.
sealed class CapabilityMismatch {
  const CapabilityMismatch(this.handlerType);

  /// The [Handler.handlerType] the disagreement is about.
  final String handlerType;
}

/// An operation kind the other peer holds and this build cannot decode.
final class MissingOperationKind extends CapabilityMismatch {
  /// Constructor
  const MissingOperationKind({
    required String handlerType,
    required this.kind,
  }) : super(handlerType);

  /// The kind byte (`OperationEnvelope.kind`) that cannot be decoded.
  final int kind;

  @override
  bool operator ==(Object other) =>
      other is MissingOperationKind &&
      other.handlerType == handlerType &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(handlerType, kind);

  @override
  String toString() => '$handlerType(kind $kind)';
}

/// A handler type the other peer holds and this build says nothing about.
///
/// Only ever a mismatch against a [SyncCapabilities.complete] description: one
/// that names every type a build reads, so a type left out is one it cannot
/// read at all. It is reported once for the type rather than once per kind —
/// the reason is not a missing kind, it is a missing handler.
final class UnknownHandlerType extends CapabilityMismatch {
  /// Constructor
  const UnknownHandlerType({required String handlerType}) : super(handlerType);

  @override
  bool operator ==(Object other) =>
      other is UnknownHandlerType && other.handlerType == handlerType;

  @override
  int get hashCode => handlerType.hashCode;

  @override
  String toString() => '$handlerType(not readable by this build)';
}

/// A snapshot blob outside the range of layouts this build reads.
///
/// A blob is refused whole, so the two peers cannot share a snapshot for this
/// handler type at all. The two subclasses say which way it missed, because
/// they call for different fixes: one needs a newer build, the other names a
/// layout this build stopped reading on purpose.
sealed class SnapshotBlobOutOfRange extends CapabilityMismatch {
  /// Records that [handlerType] holds a blob at [holds], outside [reads].
  const SnapshotBlobOutOfRange({
    required String handlerType,
    required this.reads,
    required this.holds,
  }) : super(handlerType);

  /// The range of layouts this build reads.
  final BlobVersionRange reads;

  /// The version of the other peer's blob that falls outside it.
  final int holds;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is SnapshotBlobOutOfRange &&
      other.handlerType == handlerType &&
      other.reads == reads &&
      other.holds == holds;

  @override
  int get hashCode => Object.hash(runtimeType, handlerType, reads, holds);
}

/// A blob written by a build newer than this one; only a newer build reads it.
final class SnapshotBlobTooNew extends SnapshotBlobOutOfRange {
  /// Constructor
  const SnapshotBlobTooNew({
    required super.handlerType,
    required super.reads,
    required super.holds,
  });

  @override
  String toString() =>
      '$handlerType(snapshot blob v$holds is newer than $reads)';
}

/// A blob in a layout this build no longer reads.
///
/// The handler raised [Handler.minReadableSnapshotBlobVersion] past it, so the
/// migration that used to carry that layout forward is gone.
final class SnapshotBlobTooOld extends SnapshotBlobOutOfRange {
  /// Constructor
  const SnapshotBlobTooOld({
    required super.handlerType,
    required super.reads,
    required super.holds,
  });

  @override
  String toString() =>
      '$handlerType(snapshot blob v$holds is older than $reads)';
}

/// A [DocumentCapabilities] on the wire.
///
/// `crdt_lf` describes what a build can read and what a document's data holds;
/// this adds the JSON form the handshake carries, and the comparison that
/// decides whether the two fit together.
class SyncCapabilities {
  /// Wraps a description produced by `crdt_lf`.
  ///
  /// [complete] says whether it names **every** handler type this build can
  /// read. Only a description stated by hand can promise that; one derived
  /// from a document knows the handlers opened so far and no more.
  const SyncCapabilities(this.capabilities, {this.complete = false});

  /// Reads capabilities from the JSON form written by [toJson].
  factory SyncCapabilities.fromJson(
    Map<String, dynamic> json, {
    bool complete = false,
  }) {
    return SyncCapabilities(
      DocumentCapabilities({
        for (final entry in json.entries)
          entry.key: _formatsFromJson(entry.value as Map<String, dynamic>),
      }),
      complete: complete,
    );
  }

  /// What the peer says, keyed by [Handler.handlerType].
  final DocumentCapabilities capabilities;

  /// Whether this names every handler type the peer can read.
  ///
  /// It decides what silence about a type means. A **complete** description
  /// that leaves a type out says the peer cannot read it, and the peer is
  /// refused. An incomplete one only says the type was not mentioned, so it is
  /// passed over — refusing on it would turn the ordinary shape of an app
  /// (open a handler, connect, open another) into a permanent refusal.
  final bool complete;

  /// Whether this claims nothing at all.
  ///
  /// **An empty description is not a claim.** A build that could read nothing
  /// at all would have no reason to sync, so an empty map never means "this
  /// peer reads nothing" — it means the peer had nothing to say yet, usually
  /// because its handlers open after it connects. Sending it as a claim, or
  /// reading it as one, refuses a working client for good.
  bool get isEmpty => capabilities.isEmpty;

  /// The reasons this build cannot handle what [requirements] ask for.
  ///
  /// A type this description names is checked in full: a kind it lacks, or a
  /// snapshot blob written with another layout, is a refusal. A type it does
  /// **not** name is a refusal only when this description is [complete] — see
  /// that field for why silence cannot be read as "cannot" otherwise.
  ///
  /// The two sides are different types on purpose. Capabilities are what a
  /// peer can read and requirements are what data asks for; neither contains
  /// the other, and taking them in the wrong order would quietly answer the
  /// opposite question.
  ///
  /// An empty result means everything [requirements] ask for is readable here.
  List<CapabilityMismatch> missingFrom(DocumentRequirements requirements) {
    if (isEmpty) {
      return const [];
    }

    final missing = <CapabilityMismatch>[];

    for (final entry in requirements.byHandlerType.entries) {
      final mine = capabilities[entry.key];
      if (mine == null) {
        if (complete) {
          // Not one entry per kind: what is missing is the handler.
          missing.add(UnknownHandlerType(handlerType: entry.key));
        }
        continue;
      }

      for (final kind in entry.value.operationKinds) {
        if (!mine.operationKinds.contains(kind)) {
          missing.add(
            MissingOperationKind(handlerType: entry.key, kind: kind),
          );
        }
      }

      // Only when both sides state a range. A type described from change
      // envelopes alone carries no snapshot version, and silence is not a
      // disagreement.
      //
      // Two comparisons, not an intersection: this build reads everything
      // between its own ends, so the data fits when both of its ends do.
      final reads = mine.blobVersions;
      final holds = entry.value.blobVersions;
      if (reads != null && holds != null) {
        if (holds.max > reads.max) {
          missing.add(
            SnapshotBlobTooNew(
              handlerType: entry.key,
              reads: reads,
              holds: holds.max,
            ),
          );
        }
        if (holds.min < reads.min) {
          missing.add(
            SnapshotBlobTooOld(
              handlerType: entry.key,
              reads: reads,
              holds: holds.min,
            ),
          );
        }
      }
    }

    return missing;
  }

  /// The JSON form:
  /// `{"CRDTFugueTextHandler": {"kinds": [0, 1, 2],
  /// "blob": {"min": 1, "max": 1}}}`.
  ///
  /// Kinds are sorted, so the same capabilities always encode to the same
  /// JSON. `blob` is left out when no range is known.
  Map<String, dynamic> toJson() {
    return {
      for (final entry in capabilities.byHandlerType.entries)
        entry.key: <String, dynamic>{
          'kinds': entry.value.operationKinds.toList()..sort(),
          if (entry.value.blobVersions case final blob?)
            'blob': {'min': blob.min, 'max': blob.max},
        },
    };
  }

  @override
  String toString() => 'SyncCapabilities(${toJson()})';
}

HandlerFormats _formatsFromJson(Map<String, dynamic> json) {
  final blob = json['blob'] as Map<String, dynamic>?;

  return HandlerFormats(
    operationKinds: (json['kinds'] as List<dynamic>).cast<int>().toSet(),
    blobVersions: blob == null
        ? null
        : BlobVersionRange(blob['min'] as int, blob['max'] as int),
  );
}
