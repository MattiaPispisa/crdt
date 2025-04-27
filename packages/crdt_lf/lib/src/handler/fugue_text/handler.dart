import 'package:crdt_lf/src/algorithm/fugue/element_id.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/change/change.dart';
import 'package:crdt_lf/src/document.dart';
import 'package:crdt_lf/src/handler/handler.dart';
import 'package:crdt_lf/src/operation/id.dart';
import 'package:crdt_lf/src/operation/operation.dart';
import 'package:crdt_lf/src/operation/type.dart';
import 'package:crdt_lf/src/utils/set.dart';
part 'operation.dart';

/// CRDT Text implementation with the Fugue algorithm
///
/// A CRDTFugueText is a text data structure that uses the Fugue algorithm ([The Art of the Fugue: Minimizing Interleaving in Collaborative Text Editing](https://arxiv.org/abs/2305.00583)) to minimize interleaving.
/// It provides methods for inserting, deleting, and accessing text content.
class CRDTFugueTextHandler extends Handler {
  /// Constructor that initializes a new Fugue text handler
  CRDTFugueTextHandler(this._doc, this._id) : super(_doc);

  /// The document that owns this handler
  final CRDTDocument _doc;

  /// The ID of this handler in the document
  final String _id;

  /// The Fugue tree that represents the text
  FugueTree<String> _tree = FugueTree<String>.empty();

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
    if (text.isEmpty) return;

    // Find the node at position index - 1 (or root node if index is 0)
    final leftOrigin = index == 0
        ? FugueElementID.nullID()
        : _tree.findNodeAtPosition(index - 1);

    // Find the next node after leftOrigin
    final rightOrigin = _tree.findNextNode(leftOrigin);

    // Insert first character
    final firstNodeID = FugueElementID(_doc.peerId, _counter++);
    _doc.createChange(
      _FugueTextInsertOperation.fromHandler(
        this,
        newNodeID: firstNodeID,
        text: text[0],
        leftOrigin: leftOrigin,
        rightOrigin: rightOrigin,
      ),
    );

    // Insert remaining characters as right children of the previous character
    FugueElementID previousID = firstNodeID;
    for (int i = 1; i < text.length; i++) {
      final newNodeID = FugueElementID(_doc.peerId, _counter++);
      _doc.createChange(
        _FugueTextInsertOperation.fromHandler(
          this,
          newNodeID: newNodeID,
          text: text[i],
          leftOrigin: previousID,
          rightOrigin:
              rightOrigin, // Use the same rightOrigin for all characters in the chain
        ),
      );
      previousID = newNodeID;
    }

    _invalidateCache();
  }

  /// Deletes [count] characters starting from position [index]
  void delete(int index, int count) {
    // For each character to delete
    for (int i = 0; i < count; i++) {
      // Find the node at position index (which is now index + i since we've deleted i characters)
      final nodeID = _tree.findNodeAtPosition(index + i);

      // If the node exists, create a delete operation
      if (!nodeID.isNull) {
        _doc.createChange(
          _FugueTextDeleteOperation.fromHandler(
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
    if (_cachedText != null && setEquals(_cachedVersion, currentVersion)) {
      return _cachedText!;
    }

    // Compute state from scratch
    final state = _computeState();

    // Store state in cache
    _cachedText = state;
    _cachedVersion = Set.from(currentVersion);

    return state;
  }

  @override
  String getState() {
    return value;
  }

  /// Gets the length of the text
  int get length => value.length;

  /// Computes the current state of the text from document operations
  String _computeState() {
    _tree = FugueTree.empty();

    // TODO: this is wrong, we should not need to insert the initial state
    insert(0, _initialState());

    // Get all operations from the document
    final changes = _doc.exportChanges().sorted();

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
      }
    }

    // Return the resulting text
    return _tree.values().join('');
  }

  /// Gets the initial state of the text
  String _initialState() {
    final snapshot = lastSnapshot();
    if (snapshot is String) {
      return snapshot;
    }

    return '';
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
