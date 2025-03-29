/// CRDT Text implementation
///
/// A CRDTText is a text data structure that uses CRDT for conflict-free collaboration.
/// It provides methods for inserting, deleting, and accessing text content.

import 'package:crdt_lf/src/change/change.dart';
import 'package:crdt_lf/src/operation/type.dart';

import '../../document.dart';
import '../../operation/id.dart';
import '../../operation/operation.dart';
import '../handler.dart';

part 'operation.dart';

/// A text data structure that uses CRDT for conflict-free collaboration
class CRDTTextHandler extends Handler {
  /// Creates a new CRDTText with the given document and ID
  CRDTTextHandler(this._doc, this._id);

  /// The document that owns this text
  final CRDTDocument _doc;

  /// The ID of this text in the document
  final String _id;

  @override
  String get id => _id;

  /// The cached state of the text
  String? _cachedState;

  /// The version at which the cached state was computed
  Set<OperationId>? _cachedVersion;

  /// Inserts [text] at the specified [index]
  void insert(int index, String text) {
    _doc.createChange(
      _TextInsertOperation.fromHandler(this, index: index, text: text),
    );
    _invalidateCache();
  }

  /// Deletes [count] characters starting at the specified [index]
  void delete(int index, int count) {
    _doc.createChange(
      _TextDeleteOperation.fromHandler(this, index: index, count: count),
    );
    _invalidateCache();
  }

  /// Gets the current state of the text
  String get value {
    // Check if the cached state is still valid
    final currentVersion = _doc.version;
    if (_cachedState != null && _cachedVersion == currentVersion) {
      return _cachedState!;
    }

    // Compute the state from scratch
    final state = _computeState();

    // Cache the state
    _cachedState = state;
    _cachedVersion = Set.from(currentVersion);

    return state;
  }

  /// Gets the length of the text
  int get length => value.length;

  /// Computes the current state of the text from the document's changes
  String _computeState() {
    final buffer = StringBuffer();

    // Get all changes from the document
    final changes = _doc.exportChanges().sortedByHlc();

    // Apply changes in order
    final opFactory = _TextOperationFactory(this);
    for (final change in changes) {
      final payload = change.payload;

      final operation = opFactory.fromPayload(payload);

      if (operation is _TextInsertOperation) {
        final index = operation.index;
        final text = operation.text;

        // Insert at the specified index, or at the end if the index is out of bounds
        final currentText = buffer.toString();
        if (index <= currentText.length) {
          buffer.clear();
          buffer.write(currentText.substring(0, index));
          buffer.write(text);
          buffer.write(currentText.substring(index));
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
          buffer.clear();
          buffer.write(currentText.substring(0, index));
          buffer.write(currentText.substring(index + actualCount));
        }
      }
    }

    return buffer.toString();
  }

  /// Invalidates the cached state
  void _invalidateCache() {
    _cachedState = null;
    _cachedVersion = null;
  }

  /// Returns a string representation of this text
  @override
  String toString() {
    return 'CRDTText($_id, "${value.length > 20 ? value.substring(0, 20) + "..." : value}")';
  }
}
