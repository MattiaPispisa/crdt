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

  /// Inserts [text] at the specified [index]
  void insert(int index, String text) {
    final operation = _TextInsertOperation.fromHandler(
      this,
      index: index,
      text: text,
    );
    doc.registerOperation(operation);
  }

  /// Deletes [count] characters starting at the specified [index]
  void delete(int index, int count) {
    final operation = _TextDeleteOperation.fromHandler(
      this,
      index: index,
      count: count,
    );
    doc.registerOperation(operation);
  }

  /// Updates the text at the specified [index]
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

  /// Gets the length of the text
  int get length => value.length;

  /// Computes the current state of the text from the document's changes
  String _computeState() {
    // Replay on a mutable list of code units: each operation costs a
    // single splice instead of rebuilding the whole string.
    final units = _initialState().codeUnits.toList();

    // Apply changes in order
    for (final operation in operations()) {
      _applyOperationToUnits(units, operation);
    }

    return String.fromCharCodes(units);
  }

  /// Applies a single operation to a mutable list of code units
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
      units.insertAll(index, text.codeUnits);
    } else {
      units.addAll(text.codeUnits);
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
      final replacedCount = min(text.length, remainingLength);
      units.setRange(index, index + replacedCount, text.codeUnits);
    }
  }

  @override
  String? incrementCachedState({
    required Operation operation,
    required String state,
  }) {
    // A single concatenation instead of a StringBuffer round-trip.
    if (operation is _TextInsertOperation) {
      final index = operation.index;
      if (index <= state.length) {
        return state.substring(0, index) +
            operation.text +
            state.substring(index);
      }
      return state + operation.text;
    } else if (operation is _TextDeleteOperation) {
      final index = operation.index;
      if (index >= state.length) {
        return state;
      }
      final end = min(index + operation.count, state.length);
      return state.substring(0, index) + state.substring(end);
    } else if (operation is _TextUpdateOperation) {
      final index = operation.index;
      if (index >= state.length) {
        return state;
      }
      final text = operation.text;
      final replacedCount = min(text.length, state.length - index);
      return state.substring(0, index) +
          text.substring(0, replacedCount) +
          state.substring(index + replacedCount);
    }
    return state;
  }

  @override
  Operation? compound(Operation accumulator, Operation current) {
    if (accumulator is _TextInsertOperation &&
        current is _TextInsertOperation &&
        _isContiguousInsertion(accumulator, current)) {
      final buffer = StringBuffer()
        ..write(
          accumulator.text.substring(0, current.index - accumulator.index),
        )
        ..write(current.text)
        ..write(
          accumulator.text.substring(current.index - accumulator.index),
        );
      return _TextInsertOperation.fromHandler(
        this,
        index: accumulator.index,
        text: buffer.toString(),
      );
    }
    if (accumulator is _TextInsertOperation &&
        current is _TextDeleteOperation &&
        _isDeletingPartialInsertion(accumulator, current)) {
      final buffer = StringBuffer()
        ..write(
          accumulator.text.substring(0, current.index - accumulator.index),
        )
        ..write(
          accumulator.text.substring(
            current.index - accumulator.index + current.count,
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
    return accumulator.index + accumulator.text.length >= current.index;
  }

  bool _isDeletingPartialInsertion(
    _TextInsertOperation accumulator,
    _TextDeleteOperation current,
  ) {
    return current.index >= accumulator.index &&
        current.index + current.count <=
            accumulator.index + accumulator.text.length;
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
    final truncated =
        value.length > 20 ? '${value.substring(0, 20)}...' : value;
    return 'CRDTText($_id, "$truncated")';
  }
}
