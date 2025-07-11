import 'dart:math';

import 'package:crdt_lf/src/change/change.dart';
import 'package:crdt_lf/src/handler/handler.dart';
import 'package:crdt_lf/src/operation/operation.dart';
import 'package:crdt_lf/src/operation/type.dart';

part 'operation.dart';

/// CRDT Text implementation
///
/// A CRDTText is a text data structure
/// that uses CRDT for conflict-free collaboration.
/// It provides methods for inserting, deleting, and accessing text content.
class CRDTTextHandler extends Handler<String> {
  /// Creates a new CRDTText with the given document and ID
  CRDTTextHandler(super.doc, this._id);

  /// The ID of this text in the document
  final String _id;

  @override
  String get id => _id;

  /// Inserts [text] at the specified [index]
  void insert(int index, String text) {
    doc.createChange(
      _TextInsertOperation.fromHandler(this, index: index, text: text),
    );
    invalidateCache();
  }

  /// Deletes [count] characters starting at the specified [index]
  void delete(int index, int count) {
    doc.createChange(
      _TextDeleteOperation.fromHandler(this, index: index, count: count),
    );
    invalidateCache();
  }

  /// Updates the text at the specified [index]
  void update(int index, String text) {
    doc.createChange(
      _TextUpdateOperation.fromHandler(
        this,
        index: index,
        text: text,
      ),
    );
    invalidateCache();
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

      if (operation is _TextInsertOperation) {
        final index = operation.index;
        final text = operation.text;

        // Insert at the specified index,
        // or at the end if the index is out of bounds
        final currentText = buffer.toString();
        if (index <= currentText.length) {
          buffer
            ..clear()
            ..write(currentText.substring(0, index))
            ..write(text)
            ..write(currentText.substring(index));
        } else {
          buffer.write(text);
        }
      } else if (operation is _TextDeleteOperation) {
        final index = operation.index;
        final count = operation.count;

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
      } else if (operation is _TextUpdateOperation) {
        final index = operation.index;
        final text = operation.text;

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
    }

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
