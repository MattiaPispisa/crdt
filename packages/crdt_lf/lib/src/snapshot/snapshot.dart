import 'dart:convert';
import 'package:crdt_lf/src/peer_id.dart';
import 'package:crypto/crypto.dart';
import 'package:crdt_lf/src/operation/id.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Represents a snapshot of a CRDTDocument's state at a specific version.
class Snapshot {
  /// Creates a [Snapshot]
  const Snapshot({
    required this.id,
    required this.versionVector,
    required this.data,
  });

  /// A stable identifier derived from the version.
  final String id;

  /// The timestamp of the snapshot.
  final Map<PeerId, HybridLogicalClock> versionVector;

  /// The actual data representing the snapshot state.
  final Map<String, dynamic> data;

  /// Creates a [Snapshot] from a [version].
  factory Snapshot.create({
    required Set<OperationId> version,
    required Map<String, dynamic> data,
  }) {
    return Snapshot(
      id: _generateIdFromVersion(version),
      versionVector: _generateVersionVector(version),
      data: data,
    );
  }

  /// Converts the [Snapshot] to a JSON object
  Map<String, dynamic> toJson() => {
        'id': id,
        'data': data,
        'versionVector': versionVector.entries
            .map((e) => MapEntry(e.key.toString(), e.value.toInt64()))
            .toList(),
      };

  /// Converts a JSON object to a [Snapshot]
  static Snapshot fromJson(Map<String, dynamic> json) => Snapshot(
        id: json['id'],
        data: Map<String, dynamic>.from(json['data']),
        versionVector: json['versionVector'].map((e) => MapEntry(
              PeerId.parse(e.key),
              HybridLogicalClock.fromInt64(e.value),
            )),
      );

  /// Generates a stable SHA-256 hash ID from the version set.
  static String _generateIdFromVersion(Set<OperationId> version) {
    if (version.isEmpty) {
      // Define a specific ID for the empty version state
      // Hashing an empty string or using a constant are options.
      return sha256.convert(utf8.encode('')).toString();
    }
    // 1. Convert OperationIds to stable strings
    final List<String> versionStrings =
        version.map((opId) => opId.toString()).toList();
    // 2. Sort the strings for stability
    versionStrings.sort();
    // 3. Concatenate into a single string
    final concatenatedString = versionStrings.join(); // Join without delimiter
    // 4. Hash the concatenated string using SHA-256
    final bytes = utf8.encode(concatenatedString);
    final digest = sha256.convert(bytes);
    // Return the hexadecimal representation of the hash
    return digest.toString();
  }

  static Map<PeerId, HybridLogicalClock> _generateVersionVector(
      Set<OperationId> version) {
    if (version.isEmpty) {
      return {};
    }
    final versionVector = <PeerId, HybridLogicalClock>{};
    for (final op in version) {
      final current = versionVector[op.peerId];
      if (current == null || op.hlc.compareTo(current) > 0) {
        versionVector[op.peerId] = op.hlc;
      }
    }

    return versionVector;
  }
}
