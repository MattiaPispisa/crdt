import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// A version vector is a map of [PeerId]s to their corresponding [HybridLogicalClock].
///
/// It represents the **latest operation for each peer** in the document.
class VersionVector {
  /// Creates a [VersionVector].
  VersionVector(Map<PeerId, HybridLogicalClock> vector)
      : vector = Map.unmodifiable(vector);

  /// Creates a [VersionVector] from a set of [OperationId]s.
  factory VersionVector.create(Set<OperationId> version) {
    if (version.isEmpty) {
      return VersionVector({});
    }
    final vector = <PeerId, HybridLogicalClock>{};
    for (final op in version) {
      final current = vector[op.peerId];
      if (current == null || op.hlc.compareTo(current) > 0) {
        vector[op.peerId] = op.hlc;
      }
    }

    return VersionVector(vector);
  }

  /// Converts a JSON object to a [VersionVector]
  static VersionVector fromJson(Map<String, dynamic> json) => VersionVector(
        (json['vector'] as Map<String, dynamic>).map(
          (peerIdStr, hlcInt64) => MapEntry(
            PeerId.parse(peerIdStr),
            HybridLogicalClock.fromInt64(hlcInt64 as int),
          ),
        ),
      );

  final Map<PeerId, HybridLogicalClock> vector;

  /// Merges two version vectors.
  ///
  /// Returns a new version vector that is the result of merging the two input vectors.
  /// The merged vector contains the most recent clock for each peer.
  VersionVector merged(VersionVector other) {
    final merged = <PeerId, HybridLogicalClock>{...vector};
    for (final entry in other.vector.entries) {
      final current = merged[entry.key];

      if (current == null || entry.value.compareTo(current) > 0) {
        merged[entry.key] = entry.value;
      }
    }

    return VersionVector(merged);
  }

  /// Whether this version vector is newer than the other.
  ///
  /// Find the most recent clock for each peer and compare them.
  bool isNewerThan(VersionVector other) {
    final mostRecent = _mostRecent();
    final otherMostRecent = other._mostRecent();

    if (mostRecent == null && otherMostRecent == null) {
      return false;
    }

    if (mostRecent != null && otherMostRecent == null) {
      return true;
    }
    if (mostRecent == null && otherMostRecent != null) {
      return false;
    }

    return mostRecent!.compareTo(otherMostRecent!) > 0;
  }

  // TODO: da testare
  /// Whether this version vector is strictly newer than the other.
  ///
  /// This is true if this version vector has a more recent clock for **every peer**.
  bool isStrictlyNewerThan(VersionVector other) {
    for (final entry in vector.entries) {
      final otherEntry = other.vector[entry.key];
      if (otherEntry == null) {
        return false;
      }
      if (entry.value.compareTo(otherEntry) <= 0) {
        return false;
      }
    }

    return true;
  }

  /// Returns the most recent clock for this version vector.
  ///
  /// Returns null if the version vector is empty.
  HybridLogicalClock? _mostRecent() {
    HybridLogicalClock? mostRecent;
    for (final entry in vector.entries) {
      if (mostRecent == null || entry.value.compareTo(mostRecent) > 0) {
        mostRecent = entry.value;
      }
    }
    return mostRecent;
  }

  /// Converts the [VersionVector] to a JSON object
  Map<String, dynamic> toJson() => {
        'vector': vector.map(
          (peerId, hlc) => MapEntry(peerId.toString(), hlc.toInt64()),
        ),
      };

  HybridLogicalClock? operator [](PeerId peerId) => vector[peerId];
}
