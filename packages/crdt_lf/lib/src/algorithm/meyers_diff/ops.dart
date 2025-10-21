/// Diff operation types.
enum DiffOp {
  /// Equal means text shared by both sequences.
  equal,

  /// Insert means text inserted in the new text.
  insert,

  /// Remove means text removed from the old text.
  remove;
}

/// A single diff segment with an operation and the associated text.
class DiffSegment {
  /// Creates a new diff segment with the given operation and text.
  const DiffSegment({
    required this.op,
    required this.text,
    required this.oldStart,
    required this.oldEnd,
    required this.newStart,
    required this.newEnd,
  });

  /// The operation of the diff segment.
  final DiffOp op;

  /// The text of the diff segment.
  final String text;

  /// Start index in the old text (inclusive).
  /// For inserts, this is the position where text would be inserted in oldText.
  final int oldStart;

  /// End index in the old text (exclusive).
  /// For inserts, oldEnd == oldStart.
  final int oldEnd;

  /// Start index in the new text (inclusive).
  /// For removes, this is the position where text was removed from newText.
  final int newStart;

  /// End index in the new text (exclusive).
  /// For removes, newEnd == newStart.
  final int newEnd;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! DiffSegment) {
      return false;
    }
    return other.op == op &&
        other.text == text &&
        other.oldStart == oldStart &&
        other.oldEnd == oldEnd &&
        other.newStart == newStart &&
        other.newEnd == newEnd;
  }

  @override
  int get hashCode {
    return Object.hash(op, text, oldStart, oldEnd, newStart, newEnd);
  }

  @override
  String toString() {
    return 'DiffSegment(op: $op, text: $text, '
        'old: [$oldStart, $oldEnd), new: [$newStart, $newEnd))';
  }
}
