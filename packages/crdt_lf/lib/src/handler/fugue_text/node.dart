import 'element_id.dart';
import 'tree.dart';

/// Represents the side of a node in the [FugueTree] (left or right)
enum FugueSide { left, right }

/// Represents a node in the [FugueTree]
class FugueNode {
  /// Constructor that initializes a node
  FugueNode({
    required this.id,
    required this.value,
    required this.parentID,
    required this.side,
  });

  /// Unique ID of the node
  final FugueElementID id;

  /// Value of the node (null for deleted nodes)
  String? value;

  /// ID of the parent node
  final FugueElementID parentID;

  /// Side of the node relative to its parent (left or right)
  final FugueSide side;

  /// Checks if the node has been deleted
  bool get isDeleted => value == null;

  /// Serializes the node to JSON format
  Map<String, dynamic> toJson() => {
        'id': id.toJson(),
        'value': value,
        'parentID': parentID.toJson(),
        'side': side == FugueSide.left ? 'left' : 'right',
      };

  /// Creates a node from a JSON object
  factory FugueNode.fromJson(Map<String, dynamic> json) {
    return FugueNode(
      id: FugueElementID.fromJson(json['id']),
      value: json['value'],
      parentID: FugueElementID.fromJson(json['parentID']),
      side: json['side'] == 'left' ? FugueSide.left : FugueSide.right,
    );
  }

  @override
  String toString() {
    return 'FugueNode(id: $id, value: $value, parentID: $parentID, side: $side)';
  }
}
