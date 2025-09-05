import 'package:crdt_lf/crdt_lf.dart';
part 'operation.dart';

// TODO(mattia): fix and complete fugue text caching.

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

    final state = cachedState ?? _computeState();

    // Find the node at position index - 1 (or root node if index is 0)
    final leftOrigin = index == 0
        ? FugueElementID.nullID()
        : state.tree.findNodeAtPosition(index - 1);

    // Find the next node after leftOrigin
    final rightOrigin = state.tree.findNextNode(leftOrigin);

    // Insert first character
    final firstNodeID = FugueElementID(doc.peerId, _counter++);
    doc.createChange(
      _FugueTextInsertOperation.fromHandler(
        this,
        newNodeID: firstNodeID,
        text: text[0],
        leftOrigin: leftOrigin,
        rightOrigin: rightOrigin,
      ),
    );

    // Insert remaining characters as right children of the previous character
    var previousID = firstNodeID;
    for (var i = 1; i < text.length; i++) {
      final newNodeID = FugueElementID(doc.peerId, _counter++);
      doc.createChange(
        _FugueTextInsertOperation.fromHandler(
          this,
          newNodeID: newNodeID,
          text: text[i],
          leftOrigin: previousID,
          // Use the same rightOrigin for all characters in the chain
          rightOrigin: rightOrigin,
        ),
      );
      previousID = newNodeID;
    }
  }

  /// Deletes [count] characters starting from position [index]
  void delete(int index, int count) {
    final state = cachedState ?? _computeState();
    // Collect targets first to avoid index drift while deleting
    final targets = <FugueElementID>[];
    for (var i = 0; i < count; i++) {
      final nodeID = state.tree.findNodeAtPosition(index + i);
      if (!nodeID.isNull) {
        targets.add(nodeID);
      }
    }

    for (final nodeID in targets) {
      doc.createChange(
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

    final state = cachedState ?? _computeState();

    // Collect targets first to avoid index drift while updating
    final targets = <FugueElementID>[];
    for (var i = 0; i < text.length; i++) {
      final nodeID = state.tree.findNodeAtPosition(index + i);
      if (!nodeID.isNull) {
        targets.add(nodeID);
      }
    }

    for (var i = 0; i < targets.length; i++) {
      final nodeID = targets[i];
      final newNodeID = FugueElementID(doc.peerId, _counter++);
      final ch = text[i];
      doc.createChange(
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
    // Check if cache is still valid
    if (cachedState != null) {
      return cachedState!.value;
    }

    // Compute state from scratch
    final state = _computeState();

    // Store state in cache
    updateCachedState(state);

    return state.value;
  }

  @override
  FugueTextState? incrementCachedState({
    required Operation operation,
    required FugueTextState state,
  }) {
    _applyTreeOperation(state.tree, operation);
    return state..resolve();
  }

  @override
  List<FugueValueNode<String>> getSnapshotState() {
    if (cachedState != null) {
      return cachedState!.nodes;
    }

    // Compute state from scratch
    final state = _computeState();

    // Store state in cache
    updateCachedState(state);

    return state.nodes;
  }

  /// Gets the length of the text
  int get length => value.length;

  /// Computes the current state of the text from document operations
  FugueTextState _computeState() {
    final state = FugueTextState.empty();

    // Insert initial state
    state.tree.iterableInsert(0, _initialState());

    // Get all operations from the document
    final changes = doc.exportChanges().sorted();

    // Apply operations in order
    final opFactory = _FugueTextOperationFactory(this);

    for (final change in changes) {
      final operation = opFactory.fromPayload(change.payload);

      if (operation != null) {
        _applyTreeOperation(state.tree, operation);
      }
    }

    // Return the resulting text
    return state..resolve();
  }

  /// Applies a single operation to a Fugue tree
  void _applyTreeOperation(FugueTree<String> tree, Operation operation) {
    if (operation is _FugueTextInsertOperation) {
      tree.insert(
        newID: operation.newNodeID,
        value: operation.text,
        leftOrigin: operation.leftOrigin,
        rightOrigin: operation.rightOrigin,
      );
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

class FugueTextState {
  FugueTextState({
    required this.tree,
  });

  factory FugueTextState.empty() {
    return FugueTextState(tree: FugueTree<String>.empty());
  }

  final FugueTree<String> tree;
  late List<FugueValueNode<String>> nodes;
  late String value;

  void resolve() {
    nodes = tree.nodes();
    value = nodes.map((el) => el.value).join();
  }
}
