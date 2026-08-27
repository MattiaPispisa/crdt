import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/algorithm/fugue/value_node.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_sequence_handler.dart';
import 'package:crdt_lf/src/handler/handler_type.dart';

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
/// ## Index space
/// One element is one **rune** (Unicode code point).
/// Use [RuneOffsets] to work with code unit.
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final text = CRDTFugueTextHandler(doc, 'text');
/// text..insert(0, 'Hello')..insert(5, ' World');
/// print(text.value); // Prints ["Hello"]
/// ```
base class CRDTFugueTextHandler
    extends FugueSequenceHandler<String, String, FugueTextState> {
  /// Constructor that initializes a new Fugue text handler
  CRDTFugueTextHandler(super.doc, super.id);

  /// Stable type tag (minification-safe). See [Handler.handlerType].
  @override
  String get handlerType => kFugueTextHandlerType;

  @override
  late final OperationDecoders operationDecoders = {
    OperationType.kindInsert: (body) =>
        _FugueTextInsertOperation.fromBodyBytes(this, body),
    OperationType.kindDelete: (body) =>
        _FugueTextDeleteOperation.fromBodyBytes(this, body),
    OperationType.kindUpdate: (body) =>
        _FugueTextUpdateOperation.fromBodyBytes(this, body),
  };

  /// Inserts [text] at position [index], **in runes**
  void insert(int index, String text) {
    if (text.isEmpty) {
      return;
    }

    final leftOrigin = originBefore(index);
    final rightOrigin = nodeAfter(leftOrigin);

    // Generate one node per rune
    final items = <_FugueInsertItem>[];
    for (final rune in text.runes) {
      items.add(
        _FugueInsertItem(
          id: FugueElementID(doc.peerId, nextCounter()),
          text: String.fromCharCode(rune),
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

  /// Overwrites the elements starting at [index] with [text], keeping the
  /// identity of each one.
  ///
  /// Two peers updating the same element converge on one of the two values
  /// instead of keeping both, anchors taken with [stablePositionAt] keep
  /// resolving, and nothing is added to the tree. An update loses against a
  /// concurrent deletion of the same element, and stops at the end of the
  /// text instead of inserting.
  ///
  /// [index] and the length of [text] are counted in **runes**, like every
  /// other positional API of this handler.
  void update(int index, String text) {
    if (text.isEmpty) {
      return;
    }

    final runes = text.runes.toList();
    final items = <_FugueUpdateItem>[];
    for (var i = 0; i < runes.length; i++) {
      final nodeID = nodeAt(index + i);
      if (nodeID.isNull) {
        // Past the end of the text: there is nothing left to overwrite.
        break;
      }
      items.add(
        _FugueUpdateItem(
          nodeID: nodeID,
          text: String.fromCharCode(runes[i]),
        ),
      );
    }

    if (items.isEmpty) {
      return;
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
          offset += segment.newEnd - segment.newStart;
        case DiffOp.remove:
          // Remove text at adjusted position
          final count = segment.oldEnd - segment.oldStart;
          delete(segment.oldStart + offset, count);
          offset -= count;
      }
    }
  }

  /// Gets the length of the text, **in runes**
  int get length => elementCount;

  @override
  FugueTextState createEmptyState() => FugueTextState.empty();

  @override
  void applyToTree(FugueTree<String> tree, Operation operation) {
    if (operation is _FugueTextInsertOperation) {
      tree.iterableInsertChain(
        leftOrigin: operation.leftOrigin,
        rightOrigin: operation.rightOrigin,
        nodes: operation.items.map(
          (item) => FugueValueNode<String>(id: item.id, value: item.text),
        ),
      );
    } else if (operation is _FugueTextDeleteOperation) {
      for (final item in operation.items) {
        tree.delete(item.nodeID);
      }
    } else if (operation is _FugueTextUpdateOperation) {
      for (final item in operation.items) {
        tree.update(
          nodeID: item.nodeID,
          value: item.text,
          stamp: operation.stamp!,
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
    }
  }

  @override
  Operation buildDeleteOperation(List<FugueElementID> nodeIDs) {
    return _FugueTextDeleteOperation.fromHandler(
      this,
      items: nodeIDs.map((id) => _FugueDeleteItem(nodeID: id)).toList(),
    );
  }

  /// Writes the run as plain WTF-8, one sequence per element and nothing
  /// else: an element is one rune, and a rune is one WTF-8 sequence, so the
  /// blob is self-delimiting and ASCII text costs one byte per character.
  @override
  Uint8List encodeRun(List<String> values) {
    return Wtf8.encodeAll(values);
  }

  @override
  List<String> decodeRun(Uint8List blob, int length) {
    return Wtf8.decodeCodePoints(blob);
  }

  /// Returns a text representation of this handler
  @override
  String toString() {
    final text = value;
    final cut = RuneOffsets.utf16Offset(text, 20);
    final truncated = cut < text.length ? '${text.substring(0, cut)}...' : text;
    return 'CRDTFugueText($id, "$truncated")';
  }
}

/// State of the [CRDTFugueTextHandler]: the text is the concatenation of all
/// live node values.
class FugueTextState extends FugueState<String, String> {
  // Private: the tree it wraps is implementation detail, so naming it in a
  // public signature would leak it back out.
  FugueTextState._(FugueTree<String> tree) : super(tree, _join);

  /// Creates an empty text state.
  factory FugueTextState.empty() {
    return FugueTextState._(FugueTree<String>.empty());
  }

  // Collects into a list and joins it.
  static String _join(FugueTree<String> tree) => tree.values().join();
}
