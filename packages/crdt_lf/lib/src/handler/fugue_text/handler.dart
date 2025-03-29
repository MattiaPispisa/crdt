/// CRDT Text implementation with the Fugue algorithm
///
/// A CRDTFugueText is a text data structure that uses the Fugue algorithm to minimize interleaving.
/// It provides methods for inserting, deleting, and accessing text content.
import 'package:crdt_lf/src/change/change.dart';
import 'package:crdt_lf/src/document.dart';
import 'package:crdt_lf/src/handler/handler.dart';
import 'package:crdt_lf/src/operation/id.dart';
import 'package:crdt_lf/src/operation/operation.dart';
import 'package:crdt_lf/src/operation/type.dart';

import 'element_id.dart';
import 'tree.dart';

part 'operation.dart';

/// Text handler that uses the Fugue algorithm ([The Art of the Fugue: Minimizing Interleaving in Collaborative Text Editing" di Matthew Weidner e Martin Kleppmann](https://arxiv.org/abs/2305.00583)) to minimize interleaving
class CRDTFugueTextHandler extends Handler {
  /// Constructor that initializes a new Fugue text handler
  CRDTFugueTextHandler(this._doc, this._id);

  /// The document that owns this handler
  final CRDTDocument _doc;

  /// The ID of this handler in the document
  final String _id;

  /// The Fugue tree that represents the text
  final FugueTree _tree = FugueTree.empty();

  /// Counter to generate unique IDs for elements
  int _counter = 0;

  /// The version stored in cache
  Set<OperationId>? _cachedVersion;

  /// The text stored in cache
  String? _cachedText;

  @override
  String get id => _id;

  /// Inserts [text] at position [index]
  void insert(int index, String text) {
    // Find the node at position index - 1 (or root node if index is 0)
    final leftOrigin = index == 0
        ? FugueElementID.nullID()
        : _tree.findNodeAtPosition(index - 1);

    // Find the next node after leftOrigin
    final rightOrigin = _tree.findNextNode(leftOrigin);

    // Generate a new ID for the node
    final newNodeID = FugueElementID(_doc.peerId, _counter++);

    // Create and apply the insert operation
    _doc.createChange(
      _FugueInsertOperation.fromHandler(
        this,
        newNodeID: newNodeID,
        text: text,
        leftOrigin: leftOrigin,
        rightOrigin: rightOrigin,
      ),
    );

    _invalidateCache();
  }

  /// Deletes [count] characters starting from position [index]
  void delete(int index, int count) {
    // For each character to delete
    for (int i = 0; i < count; i++) {
      // Find the node at position index
      final nodeID = _tree.findNodeAtPosition(index);

      // If the node exists, create a delete operation
      if (!nodeID.isNull) {
        _doc.createChange(
          _FugueDeleteOperation.fromHandler(
            this,
            nodeID: nodeID,
          ),
        );
      }
    }

    _invalidateCache();
  }

  /// Gets the current value of the text
  String get value {
    // Check if cache is still valid
    final currentVersion = _doc.version;
    if (_cachedText != null && _cachedVersion == currentVersion) {
      return _cachedText!;
    }

    // Compute state from scratch
    final state = _computeState();

    // Store state in cache
    _cachedText = state;
    _cachedVersion = Set.from(currentVersion);

    return state;
  }

  /// Gets the length of the text
  int get length => value.length;

  /// Computes the current state of the text from document operations
  String _computeState() {
    // Get all operations from the document
    final changes = _doc.exportChanges().sortedByHlc();

    // Apply operations in order
    final opFactory = _FugueOperationFactory(this);
    for (final change in changes) {
      final operation = opFactory.fromPayload(change.payload);

      if (operation is _FugueInsertOperation) {
        _tree.insert(
          newID: operation.newNodeID,
          value: operation.text,
          leftOrigin: operation.leftOrigin,
          rightOrigin: operation.rightOrigin,
        );
      } else if (operation is _FugueDeleteOperation) {
        _tree.delete(operation.nodeID);
      }
    }

    // Return the resulting text
    return _tree.values().join('');
  }

  /// Invalidates the cache
  void _invalidateCache() {
    _cachedText = null;
    _cachedVersion = null;
  }

  /// Returns a text representation of this handler
  @override
  String toString() {
    return 'CRDTFugueText($_id, "${value.length > 20 ? value.substring(0, 20) + "..." : value}")';
  }
}
