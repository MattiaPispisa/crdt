import 'package:crdt_lf/crdt_lf.dart' show FugueTree;
import 'package:crdt_lf/src/algorithm/fugue/element_id.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart' show FugueTree;

/// Represents the side of a node in the [FugueTree] (left or right)
enum FugueSide { left, right }

/// Represents a node in the [FugueTree]
class FugueNode<T> {
  /// Constructor that initializes a node
  FugueNode({
    required this.id,
    required this.value,
    required this.parentID,
    required this.side,
  });

  /// Creates a node from a JSON object
  factory FugueNode.fromJson(Map<String, dynamic> json) {
    return FugueNode<T>(
      id: FugueElementID.fromJson(json['id']),
      value: json['value'],
      parentID: FugueElementID.fromJson(json['parentID']),
      side: json['side'] == 'left' ? FugueSide.left : FugueSide.right,
    );
  }

  /// Unique ID of the node
  final FugueElementID id;

  /// Value of the node (null for deleted nodes)
  T? value;

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

  @override
  String toString() {
    return 'FugueNode(id: $id, value: $value, parentID: $parentID, side: $side)';
  }
}
