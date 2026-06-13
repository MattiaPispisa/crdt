import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_handler.dart';

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
class CRDTFugueTextHandler
    extends FugueHandler<String, String, FugueTextState> {
  /// Constructor that initializes a new Fugue text handler
  CRDTFugueTextHandler(super.doc, super.id);

  @override
  late final OperationFactory operationFactory =
      _FugueTextOperationFactory(this).fromBytes;

  /// Inserts [text] at position [index]
  void insert(int index, String text) {
    if (text.isEmpty) {
      return;
    }

    final leftOrigin = originBefore(index);
    final rightOrigin = nodeAfter(leftOrigin);

    // Generate one node per character
    final items = <_FugueInsertItem>[];
    for (var i = 0; i < text.length; i++) {
      items.add(
        _FugueInsertItem(
          id: FugueElementID(doc.peerId, nextCounter()),
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

  /// Updates the text at position [index]
  void update(int index, String text) {
    if (text.isEmpty) {
      return;
    }

    // Collect targets first to avoid index drift while updating
    final targets = <FugueElementID>[];
    for (var i = 0; i < text.length; i++) {
      final nodeID = nodeAt(index + i);
      if (!nodeID.isNull) {
        targets.add(nodeID);
      }
    }

    if (targets.isEmpty) {
      return;
    }

    final items = <_FugueUpdateItem>[];
    for (var i = 0; i < targets.length; i++) {
      items.add(
        _FugueUpdateItem(
          nodeID: targets[i],
          newNodeID: FugueElementID(doc.peerId, nextCounter()),
          text: text[i],
        ),
      );
    }

    doc.registerOperation(
      _FugueTextUpdateOperation.fromHandler(this, items: items),
    );
  }

  /// Changes the entire text to [newText] using the
  /// [Myers diff algorithm](https://link.springer.com/article/10.1007/BF01840446).
  ///
  /// This method computes the differences between the current text
  /// and [newText] using the [Myers diff algorithm](http://www.xmailserver.org/diff2.pdf),
  /// then converts these differences into a series of
  /// atomic [insert] and [delete] operations.
  ///
  /// Since this method may generate multiple operations,
  /// it is recommended to use it within a [CRDTDocument.runInTransaction]
  /// for better performance and atomicity.
  ///
  /// ## Example
  /// ```dart
  /// final text = CRDTFugueTextHandler(doc, 'text');
  /// text.insert(0, 'Hello World');
  ///
  /// // Using change within a transaction
  /// doc.runInTransaction(() {
  ///   text.change('Hello Brave New World');
  /// });
  /// // Internally generates: delete(' '), insert(' Brave New ')
  /// ```
  void change(String newText) {
    final diff = myersDiff(value, newText);

    // Track offset as text length changes during operations
    var offset = 0;

    for (final segment in diff) {
      switch (segment.op) {
        case DiffOp.equal:
          // Nothing to do, text is already correct
          break;
        case DiffOp.insert:
          // Insert new text at adjusted position
          insert(segment.oldStart + offset, segment.text);
          offset += segment.text.length;
          break;
        case DiffOp.remove:
          // Remove text at adjusted position
          delete(segment.oldStart + offset, segment.text.length);
          offset -= segment.text.length;
          break;
      }
    }
  }

  /// Gets the length of the text
  int get length => value.length;

  @override
  FugueTextState createEmptyState() => FugueTextState.empty();

  @override
  void applyToTree(FugueTree<String> tree, Operation operation) {
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
      for (final item in operation.items) {
        tree.delete(item.nodeID);
      }
    } else if (operation is _FugueTextUpdateOperation) {
      for (final item in operation.items) {
        tree.update(
          nodeID: item.nodeID,
          newID: item.newNodeID,
          newValue: item.text,
        );
      }
    }
  }

  @override
  Iterable<FugueElementID> producedElementIds(Operation operation) sync* {
    if (operation is _FugueTextInsertOperation) {
      for (final item in operation.items) {
        yield item.id;
      }
    } else if (operation is _FugueTextUpdateOperation) {
      for (final item in operation.items) {
        yield item.newNodeID;
      }
    }
  }

  @override
  Operation buildDeleteOperation(List<FugueElementID> nodeIDs) {
    return _FugueTextDeleteOperation.fromHandler(
      this,
      items: nodeIDs.map((id) => _FugueDeleteItem(nodeID: id)).toList(),
    );
  }

  @override
  Uint8List encodeValue(String value) {
    return Uint8List.fromList(utf8.encode(value));
  }

  @override
  String decodeValue(Uint8List bytes) {
    return utf8.decode(bytes);
  }

  /// Returns a text representation of this handler
  @override
  String toString() {
    return 'CRDTFugueText($id, '
        '"${value.length > 20 ? "${value.substring(0, 20)}..." : value}")';
  }
}

/// State of the [CRDTFugueTextHandler]: the text is the concatenation of all
/// live node values.
class FugueTextState extends FugueState<String, String> {
  /// Creates a text state over [tree].
  FugueTextState(FugueTree<String> tree) : super(tree, _join);

  /// Creates an empty text state.
  factory FugueTextState.empty() {
    return FugueTextState(FugueTree<String>.empty());
  }

  static String _join(FugueTree<String> tree) => tree.values().join();
}
