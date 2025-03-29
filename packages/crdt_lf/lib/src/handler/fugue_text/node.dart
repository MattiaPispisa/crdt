import 'element_id.dart';

/// Represents the side of a node in the Fugue tree (left or right)
enum FugueSide { left, right }

/// Represents a node in the Fugue tree
class FugueNode {
  /// Unique ID of the node
  final FugueElementID id;

  /// Value of the node (null for deleted nodes)
  String? value;

  /// ID of the parent node
  final FugueElementID parentID;

  /// Side of the node relative to its parent (left or right)
  final FugueSide side;

  /// Constructor that initializes a node
  FugueNode(this.id, this.value, this.parentID, this.side);

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
      FugueElementID.fromJson(json['id']),
      json['value'],
      FugueElementID.fromJson(json['parentID']),
      json['side'] == 'left' ? FugueSide.left : FugueSide.right,
    );
  }

  @override
  String toString() {
    return 'FugueNode(id: $id, value: $value, parentID: $parentID, side: $side)';
  }
}
