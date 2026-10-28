// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_sequence_handler.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_snapshot.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_text_sequence_handler.dart';

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
    extends FugueTextSequenceHandler<String, FugueTextState>
    with DeltaProvider<String, SequenceDelta<String>> {
  /// Constructor that initializes a new Fugue text handler
  CRDTFugueTextHandler(super.doc, super.id)
      : super(spec: CRDTFugueTextHandler.spec);

  /// The tag this kind travels under; see [Handler.handlerType].
  static const String _handlerType = 'CRDTFugueTextHandler';

  /// {@macro builtin_handler_spec}
  static const HandlerSpec<CRDTFugueTextHandler> spec = HandlerSpec(
    _handlerType,
    CRDTFugueTextHandler.new,
    formats: _formats,
  );

  /// What this build reads for this handler type.
  ///
  /// The blob range is [FugueSnapshot.version], shared by every handler built
  /// on the Fugue tree.
  static const HandlerFormats _formats = HandlerFormats(
    operationKinds: {
      OperationType.kindInsert,
      OperationType.kindDelete,
      OperationType.kindUpdate,
    },
    blobVersions: BlobVersionRange.single(FugueSnapshot.version),
  );

  /// Inserts [text] at position [index], **in runes**
  @override
  void insert(int index, String text) {
    if (text.isEmpty) {
      return;
    }

    final leftOrigin = originBefore(index);
    doc.registerOperation(
      FugueTextInsertOperation.ofText(
        this,
        leftOrigin: leftOrigin,
        rightOrigin: nodeAfter(leftOrigin),
        text: text,
      ),
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
  void change(String newText) => applyFugueTextChange(this, value, newText);

  @override
  FugueTextState createEmptyState() => FugueTextState.empty();

  @override
  String applyDelta(String base, SequenceDelta<String> delta) =>
      delta.applyToText(base);

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
