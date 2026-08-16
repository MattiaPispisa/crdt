import 'dart:math';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/handler/handler_type.dart';

part 'operation.dart';

/// # CRDT Text
///
/// ## Description
/// A CRDTText is a text data structure
/// that uses CRDT for conflict-free collaboration.
/// It provides methods for inserting, deleting, and accessing text content.
///
/// ## Index space
/// Every index and count is measured in **runes** (Unicode code points).
/// Use [RuneOffsets] to work with code unit.
///
/// ## Algorithm
/// Process operations in clock order.
/// Interleaving is handled just using the HLC.
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final text = CRDTTextHandler(doc, 'text');
/// text..insert(0, 'Hello')..insert(5, ' World!');
/// print(text.value); // Prints "Hello World!"
/// ```
class CRDTTextHandler extends Handler<String> {
  /// Creates a new CRDTText with the given document and ID
  CRDTTextHandler(super.doc, this._id);

  /// The ID of this text in the document
  final String _id;

  @override
  String get id => _id;

  /// Stable type tag (minification-safe). See [Handler.handlerType].
  @override
  String get handlerType => kTextHandlerType;

  @override
  late final OperationFactory operationFactory =
      _TextOperationFactory(this).fromBytes;

  /// Inserts [text] at the specified [index], counted **in runes**
  void insert(int index, String text) {
    final operation = _TextInsertOperation.fromHandler(
      this,
      index: index,
      text: text,
    );
    doc.registerOperation(operation);
  }

  /// Deletes [count] runes starting at the specified [index]
  void delete(int index, int count) {
    final operation = _TextDeleteOperation.fromHandler(
      this,
      index: index,
      count: count,
    );
    doc.registerOperation(operation);
  }

  /// Updates the text at the specified [index], counted **in runes**
  void update(int index, String text) {
    final operation = _TextUpdateOperation.fromHandler(
      this,
      index: index,
      text: text,
    );
    doc.registerOperation(operation);
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
  /// final text = CRDTTextHandler(doc, 'text');
  /// text.insert(0, 'Hello World');
  ///
  /// // Using change within a transaction
  /// doc.runInTransaction(() {
  ///   text.change('Hello Brave New World');
  /// });
  /// ```
  void change(String newText) {
    final currentText = value;
    final diff = myersDiff(currentText, newText);

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
          break;
        case DiffOp.remove:
          // Remove text at adjusted position
          final count = segment.oldEnd - segment.oldStart;
          delete(segment.oldStart + offset, count);
          offset -= count;
          break;
      }
    }
  }

  /// Gets the current state of the text
  String get value {
    // Check if the cached state is still valid
    if (cachedState != null) {
      return cachedState!;
    }

    // Compute the state from scratch
    final state = _computeState();

    // Cache the state
    updateCachedState(state);

    return state;
  }

  @override
  Uint8List getSnapshotState() {
    return Wtf8.encode(value);
  }

  /// Gets the length of the text, **in runes**
  int get length => RuneOffsets.length(value);

  /// Computes the current state of the text from the document's changes
  String _computeState() {
    // Replay on a mutable list of runes: each operation costs a
    // single splice instead of rebuilding the whole string.
    final units = _initialState().runes.toList();

    // Apply changes in order
    for (final operation in operations()) {
      _applyOperationToUnits(units, operation);
    }

    return String.fromCharCodes(units);
  }

  /// Applies a single operation to a mutable list of runes
  void _applyOperationToUnits(List<int> units, Operation operation) {
    if (operation is _TextInsertOperation) {
      return _unitsInsert(
        units,
        index: operation.index,
        text: operation.text,
      );
    } else if (operation is _TextDeleteOperation) {
      return _unitsDelete(
        units,
        index: operation.index,
        count: operation.count,
      );
    } else if (operation is _TextUpdateOperation) {
      return _unitsUpdate(
        units,
        index: operation.index,
        text: operation.text,
      );
    }
  }

  void _unitsInsert(
    List<int> units, {
    required int index,
    required String text,
  }) {
    // Insert at the specified index,
    // or at the end if the index is out of bounds
    if (index <= units.length) {
      units.insertAll(index, text.runes);
    } else {
      units.addAll(text.runes);
    }
  }

  void _unitsDelete(
    List<int> units, {
    required int index,
    required int count,
  }) {
    // Delete text if the index is valid
    if (index < units.length) {
      final actualCount =
          index + count > units.length ? units.length - index : count;
      units.removeRange(index, index + actualCount);
    }
  }

  void _unitsUpdate(
    List<int> units, {
    required int index,
    required String text,
  }) {
    // Update the text at the specified index,
    // truncating the replacement to the remaining length
    if (index < units.length) {
      final remainingLength = units.length - index;
      final runes = text.runes.toList();
      final replacedCount = min(runes.length, remainingLength);
      units.setRange(index, index + replacedCount, runes);
    }
  }

  @override
  String? incrementCachedState({
    required Operation operation,
    required String state,
    DeltaSink<Object?>? sink,
  }) {
    if (operation is _TextInsertOperation) {
      final at = RuneOffsets.utf16Offset(state, operation.index);
      return state.substring(0, at) + operation.text + state.substring(at);
    } else if (operation is _TextDeleteOperation) {
      final start = RuneOffsets.utf16Offset(state, operation.index);
      if (start >= state.length) {
        return state;
      }
      final end = RuneOffsets.utf16Offset(
        state,
        operation.index + operation.count,
      );
      return state.substring(0, start) + state.substring(end);
    } else if (operation is _TextUpdateOperation) {
      final start = RuneOffsets.utf16Offset(state, operation.index);
      if (start >= state.length) {
        return state;
      }
      final text = operation.text;
      // The replacement is truncated to whatever fits after the index.
      final end = RuneOffsets.utf16Offset(
        state,
        operation.index + RuneOffsets.length(text),
      );
      final replacedCount = RuneOffsets.runeIndex(state, end) - operation.index;
      return state.substring(0, start) +
          text.substring(0, RuneOffsets.utf16Offset(text, replacedCount)) +
          state.substring(end);
    }
    return state;
  }

  @override
  Operation? compound(Operation accumulator, Operation current) {
    if (accumulator is _TextInsertOperation &&
        current is _TextInsertOperation &&
        _isContiguousInsertion(accumulator, current)) {
      final split = RuneOffsets.utf16Offset(
        accumulator.text,
        current.index - accumulator.index,
      );
      final buffer = StringBuffer()
        ..write(accumulator.text.substring(0, split))
        ..write(current.text)
        ..write(accumulator.text.substring(split));
      return _TextInsertOperation.fromHandler(
        this,
        index: accumulator.index,
        text: buffer.toString(),
      );
    }
    if (accumulator is _TextInsertOperation &&
        current is _TextDeleteOperation &&
        _isDeletingPartialInsertion(accumulator, current)) {
      final removedStart = current.index - accumulator.index;
      final buffer = StringBuffer()
        ..write(
          accumulator.text.substring(
            0,
            RuneOffsets.utf16Offset(accumulator.text, removedStart),
          ),
        )
        ..write(
          accumulator.text.substring(
            RuneOffsets.utf16Offset(
              accumulator.text,
              removedStart + current.count,
            ),
          ),
        );
      return _TextInsertOperation.fromHandler(
        this,
        index: accumulator.index,
        text: buffer.toString(),
      );
    }
    if (accumulator is _TextDeleteOperation &&
        current is _TextDeleteOperation) {
      // Forward delete (repeated "Delete" key): both deletions share the
      // same anchor index, so the second removes what shifted into place.
      if (current.index == accumulator.index) {
        return _TextDeleteOperation.fromHandler(
          this,
          index: accumulator.index,
          count: accumulator.count + current.count,
        );
      }
      // Backward delete (repeated "Backspace"): the current deletion ends
      // exactly where the accumulated one began.
      if (current.index + current.count == accumulator.index) {
        return _TextDeleteOperation.fromHandler(
          this,
          index: current.index,
          count: accumulator.count + current.count,
        );
      }
    }

    return null;
  }

  bool _isContiguousInsertion(
    _TextInsertOperation accumulator,
    _TextInsertOperation current,
  ) {
    return accumulator.index + RuneOffsets.length(accumulator.text) >=
        current.index;
  }

  bool _isDeletingPartialInsertion(
    _TextInsertOperation accumulator,
    _TextDeleteOperation current,
  ) {
    return current.index >= accumulator.index &&
        current.index + current.count <=
            accumulator.index + RuneOffsets.length(accumulator.text);
  }

  /// Gets the initial state of the text
  String _initialState() {
    final snapshot = lastSnapshot();
    if (snapshot == null) {
      return '';
    }
    return Wtf8.decode(snapshot);
  }

  /// Returns a string representation of this text
  @override
  String toString() {
    final cut = RuneOffsets.utf16Offset(value, 20);
    final truncated =
        cut < value.length ? '${value.substring(0, cut)}...' : value;
    return 'CRDTText($_id, "$truncated")';
  }
}
