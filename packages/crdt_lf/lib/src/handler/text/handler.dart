import 'dart:math';

import 'package:crdt_lf/src/change/change.dart';
import 'package:crdt_lf/src/handler/handler.dart';
import 'package:crdt_lf/src/operation/operation.dart';
import 'package:crdt_lf/src/operation/type.dart';

part 'operation.dart';

// TODO(mattia): implement compound operation

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
  String getSnapshotState() {
    return value;
  }

  /// Gets the length of the text
  int get length => value.length;

  /// Computes the current state of the text from the document's changes
  String _computeState() {
    final buffer = StringBuffer(_initialState());

    // Get all changes from the document
    final changes = doc.exportChanges().sorted();

    // Apply changes in order
    final opFactory = _TextOperationFactory(this);
    for (final change in changes) {
      final payload = change.payload;

      final operation = opFactory.fromPayload(payload);

      if (operation != null) {
        _applyOperationToBuffer(buffer, operation);
      }
    }

    return buffer.toString();
  }

  /// Applies a single operation to a StringBuffer
  void _applyOperationToBuffer(StringBuffer buffer, Operation operation) {
    if (operation is _TextInsertOperation) {
      return _bufferInsert(
        buffer,
        index: operation.index,
        text: operation.text,
      );
    } else if (operation is _TextDeleteOperation) {
      return _bufferDelete(
        buffer,
        index: operation.index,
        count: operation.count,
      );
    } else if (operation is _TextUpdateOperation) {
      return _bufferUpdate(
        buffer,
        index: operation.index,
        text: operation.text,
      );
    }
  }

  void _bufferInsert(
    StringBuffer buffer, {
    required int index,
    required String text,
  }) {
    // Insert at the specified index,
    // or at the end if the index is out of bounds
    final currentText = buffer.toString();
    if (index <= currentText.length) {
      buffer
        ..clear()
        ..write(currentText.substring(0, index))
        ..write(text)
        ..write(currentText.substring(index));
      return;
    }

    buffer.write(text);
    return;
  }

  void _bufferDelete(
    StringBuffer buffer, {
    required int index,
    required int count,
  }) {
    // Delete text if the index is valid
    final currentText = buffer.toString();
    if (index < currentText.length) {
      final actualCount = index + count > currentText.length
          ? currentText.length - index
          : count;
      buffer
        ..clear()
        ..write(currentText.substring(0, index))
        ..write(currentText.substring(index + actualCount));
    }
  }

  void _bufferUpdate(
    StringBuffer buffer, {
    required int index,
    required String text,
  }) {
    // Update the text at the specified index
    final currentText = buffer.toString();

    if (index < currentText.length) {
      buffer
        ..clear()
        ..write(currentText.substring(0, index));

      final remainingLength = currentText.length - index;
      final truncatedText =
          text.substring(0, min(text.length, remainingLength));

      buffer.write(truncatedText);

      if (remainingLength > text.length) {
        buffer.write(currentText.substring(index + text.length));
      }
    }
  }

  @override
  String? incrementCachedState({
    required Operation operation,
    required String state,
  }) {
    final buffer = StringBuffer(state);
    _applyOperationToBuffer(buffer, operation);
    return buffer.toString();
  }

  /// Gets the initial state of the text
  String _initialState() {
    final snapshot = lastSnapshot();
    if (snapshot is String) {
      return snapshot;
    }

    return '';
  }

  /// Returns a string representation of this text
  @override
  String toString() {
    final truncated =
        value.length > 20 ? '${value.substring(0, 20)}...' : value;
    return 'CRDTText($_id, "$truncated")';
  }
}
