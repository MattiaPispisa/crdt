import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// A version vector is a map of [PeerId]s
/// to their corresponding [HybridLogicalClock].
///
/// It represents the **latest operation for each peer** in the document.
class VersionVector {
  /// Creates a [VersionVector].
  VersionVector(Map<PeerId, HybridLogicalClock> vector)
      : _vector = vector,
        _immutable = false;

  /// Creates an immutable [VersionVector].
  VersionVector.immutable(Map<PeerId, HybridLogicalClock> vector)
      : _vector = Map.unmodifiable(vector),
        _immutable = true;

  /// Converts a JSON object to a [VersionVector]
  factory VersionVector.fromJson(Map<String, dynamic> json) => VersionVector(
        (json['vector'] as Map<String, dynamic>).map(
          (peerIdStr, hlcInt64) => MapEntry(
            PeerId.parse(peerIdStr),
            HybridLogicalClock.fromInt64(hlcInt64 as int),
          ),
        ),
      );

  final Map<PeerId, HybridLogicalClock> _vector;

  /// Whether the version vector is empty.
  bool get isEmpty => _vector.isEmpty;

  final bool _immutable;

  /// Updates the version vector with a new [clock] for the given [id].
  ///
  /// If the version vector is immutable, this will throw a [StateError].
  void update(PeerId id, HybridLogicalClock clock) {
    if (_immutable) {
      throw UnsupportedError('Version vector is immutable');
    }

    _vector.update(
      id,
      (value) => value.compareTo(clock) > 0 ? value : clock,
      ifAbsent: () => clock,
    );
  }

  /// Removes the [ids] from the version vector.
  ///
  /// If the version vector is immutable, this will throw a [StateError].
  void remove(Iterable<PeerId> ids) {
    if (_immutable) {
      throw UnsupportedError('Version vector is immutable');
    }

    for (final id in ids) {
      _vector.remove(id);
    }
  }

  /// Clears the version vector.
  ///
  /// If the version vector is immutable, this will throw a [StateError].
  void clear() {
    if (_immutable) {
      throw UnsupportedError('Version vector is immutable');
    }

    _vector.clear();
  }

  /// Merges two version vectors.
  ///
  /// Returns a new version vector that
  /// is the result of merging the two input vectors.
  /// The merged vector contains the most recent clock for each peer.
  VersionVector merged(VersionVector other) {
    final immutable = _immutable || other._immutable;
    final merged = <PeerId, HybridLogicalClock>{..._vector};
    for (final entry in other._vector.entries) {
      final current = merged[entry.key];

      if (current == null || entry.value.compareTo(current) > 0) {
        merged[entry.key] = entry.value;
      }
    }

    return immutable ? VersionVector.immutable(merged) : VersionVector(merged);
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

  /// Whether this version vector is strictly newer than the other.
  ///
  /// This is true if this version vector
  /// has a **more recent clock** for **every peer**.
  bool isStrictlyNewerThan(VersionVector other) {
    for (final otherEntry in other._vector.entries) {
      final current = _vector[otherEntry.key];
      if (current == null) {
        return false;
      }
      if (current.compareTo(otherEntry.value) <= 0) {
        return false;
      }
    }

    return true;
  }

  /// Whether this version vector is **strictly newer or equal** than the other.
  ///
  /// This is true if this version vector
  /// has a **more recent or equal clock** for **every peer**.
  bool isStrictlyNewerOrEqualThan(VersionVector other) {
    for (final otherEntry in other._vector.entries) {
      final current = _vector[otherEntry.key];
      if (current == null) {
        return false;
      }
      if (current.compareTo(otherEntry.value) < 0) {
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
    for (final entry in _vector.entries) {
      if (mostRecent == null || entry.value.compareTo(mostRecent) > 0) {
        mostRecent = entry.value;
      }
    }
    return mostRecent;
  }

  /// Converts the [VersionVector] to a JSON object
  Map<String, dynamic> toJson() => {
        'vector': _vector.map(
          (peerId, hlc) => MapEntry(peerId.toString(), hlc.toInt64()),
        ),
      };

  /// Returns the clock for the given [peerId].
  HybridLogicalClock? operator [](PeerId peerId) => _vector[peerId];

  /// Returns an immutable copy of the version vector.
  VersionVector immutable() {
    return VersionVector.immutable(_vector);
  }

  /// Returns an iterable of the entries in the version vector.
  Iterable<MapEntry<PeerId, HybridLogicalClock>> get entries => _vector.entries;
}
