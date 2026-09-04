import 'package:crdt_lf/crdt_lf.dart';

/// Keeps the [changes] that fall inside a version range.
///
/// [newerThan] keeps a change the vector has **not** seen, which is what a
/// peer asks for to catch up. [upTo] keeps a change the vector **has** seen,
/// which rebuilds the document as it was at that version. Passing both keeps
/// what sits between the two.
///
/// Returns [changes] itself when neither bound is given.
///
/// A backend that cannot ask its own query language this question answers it
/// here instead, on the rows it read. The test is [VersionVector.hasSeen], the
/// same one [CRDTDocument.exportChangesNewerThan] uses, so a storage and a
/// document never disagree about what a version vector covers.
List<Change> filterByVersion(
  List<Change> changes, {
  VersionVector? newerThan,
  VersionVector? upTo,
}) {
  if (newerThan == null && upTo == null) {
    return changes;
  }

  return changes.where((change) {
    if (newerThan != null && newerThan.hasSeen(change.author, change.hlc)) {
      return false;
    }
    if (upTo != null && !upTo.hasSeen(change.author, change.hlc)) {
      return false;
    }
    return true;
  }).toList();
}
