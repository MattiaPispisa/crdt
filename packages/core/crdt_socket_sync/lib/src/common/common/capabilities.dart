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

/// A snapshot blob this build would read with another layout.
///
/// A blob is refused whole, so the two peers cannot share a snapshot for this
/// handler type at all.
final class SnapshotBlobVersionMismatch extends CapabilityMismatch {
  /// Constructor
  const SnapshotBlobVersionMismatch({
    required String handlerType,
    required this.reads,
    required this.holds,
  }) : super(handlerType);

  /// The [Handler.snapshotBlobVersion] this build reads.
  final int reads;

  /// The version the other peer's blob is written with.
  final int holds;

  @override
  bool operator ==(Object other) =>
      other is SnapshotBlobVersionMismatch &&
      other.handlerType == handlerType &&
      other.reads == reads &&
      other.holds == holds;

  @override
  int get hashCode => Object.hash(handlerType, reads, holds);

  @override
  String toString() =>
      '$handlerType(snapshot blob v$holds, this build reads v$reads)';
}

/// A [DocumentCapabilities] on the wire.
///
/// `crdt_lf` describes what a build can read and what a document's data holds;
/// this adds the JSON form the handshake carries, and the comparison that
/// decides whether the two fit together.
class SyncCapabilities {
  /// Wraps a description produced by `crdt_lf`.
  const SyncCapabilities(this.capabilities);

  /// Reads capabilities from the JSON form written by [toJson].
  factory SyncCapabilities.fromJson(Map<String, dynamic> json) {
    return SyncCapabilities(
      DocumentCapabilities({
        for (final entry in json.entries)
          entry.key: _capabilityFromJson(entry.value as Map<String, dynamic>),
      }),
    );
  }

  /// What the peer says, keyed by [Handler.handlerType].
  final DocumentCapabilities capabilities;

  /// The reasons this build cannot handle what [other] holds.
  ///
  /// An empty result means everything [other] holds is readable here.
  List<CapabilityMismatch> missingFrom(SyncCapabilities other) {
    final missing = <CapabilityMismatch>[];

    for (final entry in other.capabilities.byHandlerType.entries) {
      final mine = capabilities[entry.key];

      for (final kind in entry.value.operationKinds) {
        if (mine == null || !mine.operationKinds.contains(kind)) {
          missing.add(
            MissingOperationKind(handlerType: entry.key, kind: kind),
          );
        }
      }

      // Only when both sides know one. A type described from change envelopes
      // alone carries no snapshot version, and silence is not a disagreement.
      final reads = mine?.snapshotBlobVersion;
      final holds = entry.value.snapshotBlobVersion;
      if (reads != null && holds != null && reads != holds) {
        missing.add(
          SnapshotBlobVersionMismatch(
            handlerType: entry.key,
            reads: reads,
            holds: holds,
          ),
        );
      }
    }

    return missing;
  }

  /// The JSON form:
  /// `{"CRDTFugueTextHandler": {"kinds": [0, 1, 2], "blob": 1}}`.
  ///
  /// Kinds are sorted so the same capabilities always encode to the same JSON.
  Map<String, dynamic> toJson() {
    return {
      for (final entry in capabilities.byHandlerType.entries)
        entry.key: <String, dynamic>{
          'kinds': entry.value.operationKinds.toList()..sort(),
          if (entry.value.snapshotBlobVersion != null)
            'blob': entry.value.snapshotBlobVersion,
        },
    };
  }

  @override
  String toString() => 'SyncCapabilities(${toJson()})';
}

HandlerCapability _capabilityFromJson(Map<String, dynamic> json) {
  return HandlerCapability(
    operationKinds: (json['kinds'] as List<dynamic>).cast<int>().toSet(),
    snapshotBlobVersion: json['blob'] as int?,
  );
}
