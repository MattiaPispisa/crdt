import 'package:crdt_lf/src/algorithm/fugue/element_id.dart';
import 'package:crdt_lf/src/algorithm/fugue/node.dart';

/// Represents the triple of a node and its children in the Fugue tree
class FugueNodeTriple<T> {
  /// Constructor that initializes a node triple
  const FugueNodeTriple({
    required this.node,
    required this.leftChildren,
    required this.rightChildren,
  });

  /// Creates a triple from a JSON object
  factory FugueNodeTriple.fromJson(
    Map<String, dynamic> json,
  ) {
    return FugueNodeTriple<T>(
      node: FugueNode<T>.fromJson(json['node']),
      leftChildren: (json['leftChildren'] as List)
          .map((j) => FugueElementID.fromJson(j))
          .toList(),
      rightChildren: (json['rightChildren'] as List)
          .map((j) => FugueElementID.fromJson(j))
          .toList(),
    );
  }

  /// The node itself
  final FugueNode<T> node;

  /// List of left children IDs
  final List<FugueElementID> leftChildren;

  /// List of right children IDs
  final List<FugueElementID> rightChildren;

  /// Serializes the triple to JSON format
  Map<String, dynamic> toJson() => {
        'node': node.toJson(),
        'leftChildren': leftChildren.map((id) => id.toJson()).toList(),
        'rightChildren': rightChildren.map((id) => id.toJson()).toList(),
      };
}
