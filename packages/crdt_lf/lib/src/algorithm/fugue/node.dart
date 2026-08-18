import 'package:crdt_lf/src/algorithm/fugue/element_id.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart' show FugueTree;

/// Represents the side of a node in the [FugueTree] (left or right)
enum FugueSide {
  /// Left side
  left,

  /// Right side
  right,
}

/// Represents a node in the [FugueTree]
class FugueNode<T> {
  /// Constructor that initializes a node
  FugueNode({
    required this.id,
    required this.value,
    required this.parentID,
    required this.side,
    this.deleted = false,
  });

  /// Creates a node from a JSON object
  factory FugueNode.fromJson(Map<String, dynamic> json) {
    return FugueNode<T>(
      id: FugueElementID.fromJson(json['id'] as Map<String, dynamic>),
      value: json['value'] as T?,
      parentID:
          FugueElementID.fromJson(json['parentID'] as Map<String, dynamic>),
      side: json['side'] == 'left' ? FugueSide.left : FugueSide.right,
      deleted: json['deleted'] as bool? ?? json['value'] == null,
    );
  }

  /// Unique ID of the node
  final FugueElementID id;

  /// Value of the node; `null` only on the root, which stands for no element.
  ///
  /// A tombstone keeps the value it held. Reading it means checking [deleted]
  /// first: a value here does not say the node is part of the sequence.
  T? value;

  /// ID of the parent node
  final FugueElementID parentID;

  /// Side of the node relative to its parent (left or right)
  final FugueSide side;

  /// Whether this node is a tombstone.
  ///
  /// This is the only thing that says so. [value] survives a deletion, and a
  /// node out of the sequence still has one.
  bool deleted;

  /// Checks if the node has been deleted
  bool get isDeleted => deleted;

  /// Serializes the node to JSON format
  Map<String, dynamic> toJson() => {
        'id': id.toJson(),
        'value': value,
        'parentID': parentID.toJson(),
        'side': side == FugueSide.left ? 'left' : 'right',
        'deleted': deleted,
      };

  @override
  String toString() {
    return 'FugueNode(id: $id, value: $value, deleted: $deleted,'
        ' parentID: $parentID, side: $side)';
  }
}
