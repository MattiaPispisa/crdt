import 'package:crdt_lf/crdt_lf.dart';
part 'operation.dart';

/// CRDT Text implementation with the Fugue algorithm
///
/// A CRDTFugueText is a text data structure that uses the Fugue algorithm ([The Art of the Fugue: Minimizing Interleaving in Collaborative Text Editing](https://arxiv.org/abs/2305.00583)) to minimize interleaving.
/// It provides methods for inserting, deleting, and accessing text content.
class CRDTFugueTextHandler extends Handler<List<FugueValueNode<String>>> {
  /// Constructor that initializes a new Fugue text handler
  CRDTFugueTextHandler(super.doc, this._id);

  /// The ID of this handler in the document
  final String _id;

  /// The Fugue tree that represents the text
  FugueTree<String> _tree = FugueTree<String>.empty();

  /// Counter to generate unique IDs for elements
  int _counter = 0;

  /// The cached value of the text
  String? _cachedValue;

  @override
  String get id => _id;

  /// Inserts [text] at position [index]
  void insert(int index, String text) {
    if (text.isEmpty) return;

    // Find the node at position index - 1 (or root node if index is 0)
    final leftOrigin = index == 0
        ? FugueElementID.nullID()
        : _tree.findNodeAtPosition(index - 1);

    // Find the next node after leftOrigin
    final rightOrigin = _tree.findNextNode(leftOrigin);

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

    _invalidateCache();
  }

  /// Deletes [count] characters starting from position [index]
  void delete(int index, int count) {
    // For each character to delete
    for (var i = 0; i < count; i++) {
      // Find the node at position index
      // (which is now index + i since we've deleted i characters)
      final nodeID = _tree.findNodeAtPosition(index + i);

      // If the node exists, create a delete operation
      if (!nodeID.isNull) {
        doc.createChange(
          _FugueTextDeleteOperation.fromHandler(
            this,
            nodeID: nodeID,
          ),
        );
      }
    }

    _invalidateCache();
  }

  /// Updates the text at position [index]
  void update(int index, String text) {
    if (text.isEmpty) return;

    for (var i = 0; i < text.length; i++) {
      final nodeID = _tree.findNodeAtPosition(index + i);
      if (!nodeID.isNull) {
        final newNodeID = FugueElementID(doc.peerId, _counter++);
        doc.createChange(
          _FugueTextUpdateOperation.fromHandler(
            this,
            nodeID: nodeID,
            newNodeID: newNodeID,
            text: text[i],
          ),
        );
      }
    }

    _invalidateCache();
  }

  /// Gets the current value of the text
  String get value {
    // Check if cache is still valid
    if (cachedState != null && _cachedValue != null) {
      return _cachedValue!;
    }

    if (cachedState != null) {
      _cachedValue = cachedState!.map((node) => node.value).join();
      return _cachedValue!;
    }

    // Compute state from scratch
    final state = _computeState();

    // Store state in cache
    updateCachedState(state);
    _cachedValue = state.map((node) => node.value).join();

    return _cachedValue!;
  }

  @override
  List<FugueValueNode<String>> getSnapshotState() {
    if (cachedState != null) {
      return cachedState!;
    }

    // Compute state from scratch
    final state = _computeState();

    // Store state in cache
    updateCachedState(state);

    return state;
  }

  /// Gets the length of the text
  int get length => value.length;

  /// Computes the current state of the text from document operations
  List<FugueValueNode<String>> _computeState() {
    _tree = FugueTree.empty();

    // Insert initial state
    _tree.iterableInsert(0, _initialState());

    // Get all operations from the document
    final changes = doc.exportChanges().sorted();

    // Apply operations in order
    final opFactory = _FugueTextOperationFactory(this);

    for (final change in changes) {
      final operation = opFactory.fromPayload(change.payload);

      if (operation is _FugueTextInsertOperation) {
        _tree.insert(
          newID: operation.newNodeID,
          value: operation.text,
          leftOrigin: operation.leftOrigin,
          rightOrigin: operation.rightOrigin,
        );
      } else if (operation is _FugueTextDeleteOperation) {
        _tree.delete(operation.nodeID);
      } else if (operation is _FugueTextUpdateOperation) {
        _tree.update(
          nodeID: operation.nodeID,
          newID: operation.newNodeID,
          newValue: operation.text,
        );
      }
    }

    // Return the resulting text
    return _tree.nodes();
  }

  /// Gets the initial state of the text
  List<FugueValueNode<String>> _initialState() {
    final snapshot = lastSnapshot();
    if (snapshot is List<FugueValueNode<String>>) {
      return List.from(snapshot);
    }

    return [];
  }

  /// Invalidates the cache
  void _invalidateCache() {
    invalidateCache();
    _cachedValue = null;
  }

  /// Returns a text representation of this handler
  @override
  String toString() {
    return 'CRDTFugueText($_id, '
        '"${value.length > 20 ? "${value.substring(0, 20)}..." : value}")';
  }
}
