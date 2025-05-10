import 'package:crdt_lf/crdt_lf.dart';

/// Represents a node within the logical sequence
/// maintained by a Fugue-based CRDT.
///
/// This class encapsulates an actual value (`T`) present in the sequence,
/// along with its unique Fugue identifier ([FugueElementID]).
/// It's used when traversing the internal tree structure
/// to reconstruct the effective, user-visible sequence.
///
/// It contrasts with internal structural nodes of the tree
/// that might not hold user values.
class FugueValueNode<T> {
  /// Constructor that initializes a node
  const FugueValueNode({
    required this.id,
    required this.value,
  });

  /// Creates a node from a JSON object
  factory FugueValueNode.fromJson(Map<String, dynamic> json) {
    return FugueValueNode<T>(
      id: FugueElementID.fromJson(json['id'] as Map<String, dynamic>),
      value: json['value'] as T,
    );
  }

  /// Unique ID of the node
  final FugueElementID id;

  /// Value of the node (null for deleted nodes)
  final T value;

  /// Serializes the node to JSON format
  Map<String, dynamic> toJson() => {
        'id': id.toJson(),
        'value': value,
      };

  @override
  String toString() {
    return 'FugueValueNode(id: $id, value: $value)';
  }
}
