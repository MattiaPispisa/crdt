import 'element_id.dart';
import 'node.dart';

/// Represents the triple of a node and its children in the Fugue tree
class FugueNodeTriple {
  /// The node itself
  final FugueNode node;
  
  /// List of left children IDs
  final List<FugueElementID> leftChildren;
  
  /// List of right children IDs
  final List<FugueElementID> rightChildren;
  
  /// Constructor that initializes a node triple
  FugueNodeTriple(this.node, this.leftChildren, this.rightChildren);
  
  /// Serializes the triple to JSON format
  Map<String, dynamic> toJson() => {
    'node': node.toJson(),
    'leftChildren': leftChildren.map((id) => id.toJson()).toList(),
    'rightChildren': rightChildren.map((id) => id.toJson()).toList(),
  };
  
  /// Creates a triple from a JSON object
  factory FugueNodeTriple.fromJson(Map<String, dynamic> json) {
    return FugueNodeTriple(
      FugueNode.fromJson(json['node']),
      (json['leftChildren'] as List).map((j) => FugueElementID.fromJson(j)).toList(),
      (json['rightChildren'] as List).map((j) => FugueElementID.fromJson(j)).toList(),
    );
  }
}
