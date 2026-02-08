import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// A version vector is a map of [PeerId]s
/// to their corresponding [HybridLogicalClock].
///
/// It represents the **latest operation for each peer** in the document.
///
/// Example:
/// `{client1: HLC(3, 0), client2: HLC(2, 0),client3: HLC(1, 0)}`
///
/// This means that the latest operation for client1 is HLC(3, 0)
/// (same reasoning for client2 and client3)
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
            HybridLogicalClock.parse(hlcInt64 as String),
          ),
        ),
      );

  /// Decodes a [VersionVector] from bytes produced by [toBytes].
  ///
  /// Layout:
  /// - `count: uvarint`
  /// - repeated `count` times:
  ///   - `peerId: 16 bytes`
  ///   - `hlc: 8 bytes`
  factory VersionVector.fromBytes(Uint8List bytes) {
    var offset = 0;
    final countRec = UVarint.read(bytes, offset: offset);
    offset = countRec.nextOffset;

    final vector = <PeerId, HybridLogicalClock>{};
    for (var i = 0; i < countRec.value; i += 1) {
      if (offset + 24 > bytes.length) {
        throw const FormatException('Truncated VersionVector entry');
      }
      final peerId = PeerId.fromUint8List(bytes, offset: offset);
      final hlc = HybridLogicalClock.fromUint8List(bytes, offset: offset + 16);
      vector[peerId] = hlc;
      offset += 24;
    }

    if (offset != bytes.length) {
      throw const FormatException('Trailing bytes after VersionVector');
    }

    return VersionVector(vector);
  }

  /// Returns the intersection of the given [VersionVector]s.
  ///
  /// The intersection is the version vector that contains the minimum
  /// clock for each peer.
  ///
  ///
  /// ```dart
  /// final vv1 = VersionVector({
  ///   client1: HLC(2, 0),
  ///   client2: HLC(1, 0),
  /// });
  /// final vv2 = VersionVector({
  ///   client1: HLC(3, 0),
  ///   client2: HLC(2, 0),
  ///   client3: HLC(2, 0),
  /// });
  /// final intersection = VersionVector.intersection([vv1, vv2]);
  /// print(intersection); // VersionVector({
  ///   client1: HLC(2, 0),
  ///   client2: HLC(1, 0),
  /// });
  /// ```
  factory VersionVector.intersection(Iterable<VersionVector> vectors) {
    if (vectors.isEmpty) {
      return VersionVector({});
    }

    final commonMap = Map<PeerId, HybridLogicalClock>.of(vectors.first._vector);

    for (final vv in vectors.skip(1)) {
      if (commonMap.isEmpty) {
        break;
      }

      for (final key in commonMap.keys.toList()) {
        final otherVal = vv[key];

        if (otherVal == null) {
          commonMap.remove(key);
        } else {
          final currentVal = commonMap[key]!;
          commonMap[key] = currentVal <= otherVal ? currentVal : otherVal;
        }
      }
    }

    return VersionVector(commonMap);
  }

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
    final recent = mostRecent();
    final otherMostRecent = other.mostRecent();

    if (recent == null && otherMostRecent == null) {
      return false;
    }

    if (recent != null && otherMostRecent == null) {
      return true;
    }
    if (recent == null && otherMostRecent != null) {
      return false;
    }

    return recent!.compareTo(otherMostRecent!) > 0;
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
  HybridLogicalClock? mostRecent() {
    HybridLogicalClock? result;
    for (final entry in _vector.entries) {
      if (result == null || entry.value.compareTo(result) > 0) {
        result = entry.value;
      }
    }
    return result;
  }

  /// Returns the most oldest clock for this version vector.
  ///
  /// Returns null if the version vector is empty.
  HybridLogicalClock? mostOldest() {
    HybridLogicalClock? result;
    for (final entry in _vector.entries) {
      if (result == null || entry.value.compareTo(result) < 0) {
        result = entry.value;
      }
    }
    return result;
  }

  /// Converts the [VersionVector] to a JSON object
  Map<String, dynamic> toJson() => {
        'vector': _vector.map(
          (peerId, hlc) => MapEntry(peerId.toString(), hlc.toString()),
        ),
      };

  /// Encodes this version vector to a compact binary representation.
  ///
  /// See [VersionVector.fromBytes] for the layout.
  Uint8List toBytes() {
    final out = BytesBuilder(copy: false);
    UVarint.write(_vector.length, out);
    for (final entry in _vector.entries) {
      out
        ..add(entry.key.toUint8List())
        ..add(entry.value.toUint8List());
    }
    return out.toBytes();
  }

  /// Returns the clock for the given [peerId].
  HybridLogicalClock? operator [](PeerId peerId) => _vector[peerId];

  /// Returns an immutable copy of the version vector.
  VersionVector immutable() {
    return VersionVector.immutable(_copy());
  }

  /// Returns a mutable copy of the version vector.
  VersionVector mutable() {
    return VersionVector(_copy());
  }

  /// Returns an iterable copy of the entries in the version vector.
  Iterable<MapEntry<PeerId, HybridLogicalClock>> get entries => _copy().entries;

  /// Returns a copy of the version vector.
  Map<PeerId, HybridLogicalClock> _copy() {
    return _vector.map(
      (peerId, hlc) => MapEntry(peerId, hlc.copy()),
    );
  }

  @override
  String toString() {
    return 'VersionVector(vector: $_vector)';
  }
}
