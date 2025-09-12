import 'package:crdt_lf/crdt_lf.dart';
part 'operation.dart';

/// ## CRDT Text with Fugue implementation
///
/// ## Description
/// A CRDTFugueText is a text data structure that uses the Fugue algorithm ([The Art of the Fugue: Minimizing Interleaving in Collaborative Text Editing](https://arxiv.org/abs/2305.00583)) to minimize interleaving.
/// It provides methods for inserting, deleting, and accessing text content.
///
/// ## Algorithm
/// It uses the Fugue algorithm to minimize interleaving.
/// So even if two users edit the same portion of text the algorithm will
/// minimize the possibility of characters from one user being interleaved
/// with the characters from the other user.
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final text = CRDTFugueTextHandler(doc, 'text');
/// text..insert(0, 'Hello')..insert(5, ' World');
/// print(text.value); // Prints ["Hello"]
/// ```
class CRDTFugueTextHandler extends Handler<FugueTextState> {
  /// Constructor that initializes a new Fugue text handler
  CRDTFugueTextHandler(super.doc, this._id);

  /// The ID of this handler in the document
  final String _id;

  /// Counter to generate unique IDs for elements
  int _counter = 0;

  @override
  String get id => _id;

  /// Inserts [text] at position [index]
  void insert(int index, String text) {
    if (text.isEmpty) {
      return;
    }

    final state = _cachedOrComputedState();

    // Find the node at position index - 1 (or root node if index is 0)
    final leftOrigin = index == 0
        ? FugueElementID.nullID()
        : state._tree.findNodeAtPosition(index - 1);

    // Find the next node after leftOrigin
    final rightOrigin = state._tree.findNextNode(leftOrigin);

    // Generate IDs for each character preserving the previous behavior
    final items = <_FugueInsertItem>[];
    for (var i = 0; i < text.length; i++) {
      final newNodeID = FugueElementID(doc.peerId, _counter++);
      items.add(
        _FugueInsertItem(
          id: newNodeID,
          text: text[i],
        ),
      );
    }

    // Emit a single batch change containing the whole chain
    doc.registerOperation(
      _FugueTextInsertOperation.fromHandler(
        this,
        leftOrigin: leftOrigin,
        rightOrigin: rightOrigin,
        items: items,
      ),
    );
  }

  /// Deletes [count] characters starting from position [index]
  void delete(int index, int count) {
    final state = _cachedOrComputedState();
    // Collect targets first to avoid index drift while deleting
    final targets = <FugueElementID>[];
    for (var i = 0; i < count; i++) {
      final nodeID = state._tree.findNodeAtPosition(index + i);
      if (!nodeID.isNull) {
        targets.add(nodeID);
      }
    }

    for (final nodeID in targets) {
      doc.registerOperation(
        _FugueTextDeleteOperation.fromHandler(
          this,
          nodeID: nodeID,
        ),
      );
    }
  }

  /// Updates the text at position [index]
  void update(int index, String text) {
    if (text.isEmpty) {
      return;
    }

    final state = _cachedOrComputedState();

    // Collect targets first to avoid index drift while updating
    final targets = <FugueElementID>[];
    for (var i = 0; i < text.length; i++) {
      final nodeID = state._tree.findNodeAtPosition(index + i);
      if (!nodeID.isNull) {
        targets.add(nodeID);
      }
    }

    for (var i = 0; i < targets.length; i++) {
      final nodeID = targets[i];
      final newNodeID = FugueElementID(doc.peerId, _counter++);
      final ch = text[i];
      doc.registerOperation(
        _FugueTextUpdateOperation.fromHandler(
          this,
          nodeID: nodeID,
          newNodeID: newNodeID,
          text: ch,
        ),
      );
    }
  }

  /// Gets the current value of the text
  String get value {
    return _cachedOrComputedState()._value;
  }

  /// If the cached state is still valid, returns it.
  ///
  /// Otherwise, computes the state from scratch and updates the cache.
  FugueTextState _cachedOrComputedState() {
    if (cachedState != null) {
      return cachedState!;
    }

    final state = _computeState();
    updateCachedState(state);
    return state;
  }

  @override
  FugueTextState? incrementCachedState({
    required Operation operation,
    required FugueTextState state,
  }) {
    _applyTreeOperation(state._tree, operation);
    return state..resolve();
  }

  @override
  List<FugueValueNode<String>> getSnapshotState() {
    if (cachedState != null) {
      return cachedState!._nodes;
    }

    // Compute state from scratch
    final state = _computeState();

    // Store state in cache
    updateCachedState(state);

    return state._nodes;
  }

  /// Gets the length of the text
  int get length => value.length;

  /// Computes the current state of the text from document operations
  FugueTextState _computeState() {
    final state = FugueTextState.empty();

    // Insert initial state
    state._tree.iterableInsert(0, _initialState());

    // Get all operations from the document
    final changes = doc.exportChanges().sorted();

    // Apply operations in order
    final opFactory = _FugueTextOperationFactory(this);

    for (final change in changes) {
      final operation = opFactory.fromPayload(change.payload);

      if (operation != null) {
        _applyTreeOperation(state._tree, operation);
      }
    }

    // Return the resulting text
    return state..resolve();
  }

  /// Applies a single operation to a Fugue tree
  void _applyTreeOperation(FugueTree<String> tree, Operation operation) {
    if (operation is _FugueTextInsertOperation) {
      if (operation.items.isEmpty) {
        return;
      }

      // Insert first item with provided origins
      tree.insert(
        newID: operation.items.first.id,
        value: operation.items.first.text,
        leftOrigin: operation.leftOrigin,
        rightOrigin: operation.rightOrigin,
      );
      // Chain the rest to the previous inserted id, same rightOrigin
      var previousID = operation.items.first.id;
      for (final item in operation.items.skip(1)) {
        tree.insert(
          newID: item.id,
          value: item.text,
          leftOrigin: previousID,
          rightOrigin: operation.rightOrigin,
        );
        previousID = item.id;
      }
    } else if (operation is _FugueTextDeleteOperation) {
      tree.delete(operation.nodeID);
    } else if (operation is _FugueTextUpdateOperation) {
      tree.update(
        nodeID: operation.nodeID,
        newID: operation.newNodeID,
        newValue: operation.text,
      );
    }
  }

  /// Gets the initial state of the text
  List<FugueValueNode<String>> _initialState() {
    final snapshot = lastSnapshot();
    if (snapshot is List<FugueValueNode<String>>) {
      return List.from(snapshot);
    }

    return [];
  }

  // Cache is updated directly after local ops; no private invalidator needed

  /// Returns a text representation of this handler
  @override
  String toString() {
    return 'CRDTFugueText($_id, '
        '"${value.length > 20 ? "${value.substring(0, 20)}..." : value}")';
  }
}

/// fugue text state
class FugueTextState {
  /// Constructor that initializes the state
  FugueTextState({
    required FugueTree<String> tree,
  }) : _tree = tree;

  /// Factory method that initializes an empty state
  factory FugueTextState.empty() {
    return FugueTextState(tree: FugueTree<String>.empty());
  }

  /// The tree of the state
  final FugueTree<String> _tree;

  /// The nodes of the state
  late List<FugueValueNode<String>> _nodes;

  /// The value of the state
  late String _value;

  /// Resolves [_nodes] and [_value] with the [_tree]
  void resolve() {
    _nodes = _tree.nodes();
    _value = _nodes.map((el) => el.value).join();
  }
}
