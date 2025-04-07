import 'package:crdt_lf/src/peer_id.dart';

/// Represents the ID of an element in the Fugue algorithm
class FugueElementID with Comparable<FugueElementID> {
  /// ID of the replica that generated this element
  final PeerId replicaID;

  /// Local counter of the replica at the time of element creation
  final int? counter;

  /// Constructor that initializes the element ID
  const FugueElementID(this.replicaID, this.counter);

  /// Constructor to create a null ID (used for the root)
  FugueElementID.nullID()
      : replicaID = PeerId.empty(),
        counter = null;

  /// Checks if this is a null ID
  bool get isNull => counter == null;

  /// Compares two element IDs
  @override
  int compareTo(FugueElementID other) {
    if (isNull && other.isNull) {
      return 0;
    }
    if (isNull) {
      return -1;
    }
    if (other.isNull) {
      return 1;
    }

    // Compare first by replicaID
    final replicaCompare = replicaID.compareTo(other.replicaID);
    if (replicaCompare != 0) {
      return replicaCompare;
    }

    // Then by counter
    return counter!.compareTo(other.counter!);
  }

  /// Serializes the ID to JSON format
  Map<String, dynamic> toJson() => {
        'replicaID': replicaID.toString(),
        'counter': counter,
      };

  /// Creates an ID from a JSON object
  factory FugueElementID.fromJson(Map<String, dynamic> json) {
    if (json['counter'] == null) {
      return FugueElementID.nullID();
    }
    return FugueElementID(
      PeerId.parse(json['replicaID']),
      json['counter'],
    );
  }

  /// Creates an ID from a string
  factory FugueElementID.parse(String value) {
    if (value == 'null') {
      return FugueElementID.nullID();
    }

    final parts = value.split(':');
    if (parts.length != 2) {
      throw FormatException('Invalid FugueElementID format: $value');
    }

    return FugueElementID(
      PeerId.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is FugueElementID &&
        other.replicaID == replicaID &&
        other.counter == counter;
  }

  @override
  int get hashCode => Object.hash(replicaID, counter);

  @override
  String toString() {
    if (isNull) {
      return 'null';
    }
    return '$replicaID:$counter';
  }
}
