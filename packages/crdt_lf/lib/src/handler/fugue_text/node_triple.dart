import 'element_id.dart';
import 'node.dart';

/// Represents the triple of a node and its children in the Fugue tree
class FugueNodeTriple {
  /// Constructor that initializes a node triple
  const FugueNodeTriple({
    required this.node,
    required this.leftChildren,
    required this.rightChildren,
  });

  /// The node itself
  final FugueNode node;

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

  /// Creates a triple from a JSON object
  factory FugueNodeTriple.fromJson(Map<String, dynamic> json) {
    return FugueNodeTriple(
      node: FugueNode.fromJson(json['node']),
      leftChildren: (json['leftChildren'] as List)
          .map((j) => FugueElementID.fromJson(j))
          .toList(),
      rightChildren: (json['rightChildren'] as List)
          .map((j) => FugueElementID.fromJson(j))
          .toList(),
    );
  }
}
