import 'package:crdt_lf/src/algorithm/fugue/element_id.dart';
import 'package:crdt_lf/src/algorithm/fugue/node.dart';

/// Represents the triple of a node and its children in the Fugue tree
///
/// Each side allocates its list on its first child. In a text document almost
/// every node is a leaf, so an eager empty list per side would be two objects
/// per element that never hold anything.
class FugueNodeTriple<T> {
  /// Constructor that initializes a node triple with no children.
  ///
  /// Children arrive through [insertChild].
  FugueNodeTriple(this.node);

  /// Creates a triple from a JSON object
  factory FugueNodeTriple.fromJson(
    Map<String, dynamic> json,
  ) {
    List<FugueElementID>? read(String key) {
      final children = (json[key] as List)
          .map((j) => FugueElementID.fromJson(j as Map<String, dynamic>))
          .toList();
      return children.isEmpty ? null : children;
    }

    return FugueNodeTriple<T>(
      FugueNode<T>.fromJson(json['node'] as Map<String, dynamic>),
    )
      .._leftChildren = read('leftChildren')
      .._rightChildren = read('rightChildren');
  }

  /// The node itself
  final FugueNode<T> node;

  List<FugueElementID>? _leftChildren;
  List<FugueElementID>? _rightChildren;

  /// List of left children IDs, in id order.
  ///
  /// Read-only: the empty case is a shared constant. Use [insertChild] to add
  /// one.
  List<FugueElementID> get leftChildren =>
      _leftChildren ?? const <FugueElementID>[];

  /// List of right children IDs, in id order.
  ///
  /// Read-only: the empty case is a shared constant. Use [insertChild] to add
  /// one.
  List<FugueElementID> get rightChildren =>
      _rightChildren ?? const <FugueElementID>[];

  /// Puts [id] among the children on [side], at [index].
  ///
  /// The caller picks [index], because the order is the sibling order the tree
  /// keeps sorted by id.
  void insertChild(
    FugueElementID id, {
    required FugueSide side,
    required int index,
  }) {
    if (side == FugueSide.left) {
      (_leftChildren ??= <FugueElementID>[]).insert(index, id);
    } else {
      (_rightChildren ??= <FugueElementID>[]).insert(index, id);
    }
  }

  /// Serializes the triple to JSON format
  Map<String, dynamic> toJson() => {
        'node': node.toJson(),
        'leftChildren': leftChildren.map((id) => id.toJson()).toList(),
        'rightChildren': rightChildren.map((id) => id.toJson()).toList(),
      };
}
