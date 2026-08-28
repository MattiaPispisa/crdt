import 'package:crdt_lf/src/algorithm/fugue/element_id.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/delta/sequence_delta.dart';

/// Where an insert chain landed, in the coordinates of the sequence **before**
/// the operation.
///
/// Call it right after the chain went into [tree]: a chain is contiguous and
/// every element of it is new, so the place of the first one is the place of
/// all of them. That is one `O(√n)` query for the whole operation, whatever
/// the number of elements.
SequenceDelta<T> fugueInsertDelta<T>(
  FugueTree<T> tree,
  FugueElementID firstID,
  List<T> values,
) {
  if (values.isEmpty) {
    return SequenceDelta<T>.empty();
  }
  final after = tree.liveIndexAfter(firstID);
  if (after == null) {
    return SequenceDelta<T>.empty();
  }
  final at = after - 1;
  return SequenceDelta<T>([
    if (at > 0) SeqRetain<T>(at),
    SeqInsert<T>(values),
  ]);
}

/// The places of the [ids] that are still part of the sequence, ascending.
///
/// Read them **before** the elements become tombstones. Afterwards every place
/// after the first removal has moved, and the delta would describe a different
/// edit.
///
/// An id that is unknown or already a tombstone is skipped: deleting it does
/// nothing, so it moves nothing.
List<int> fugueLivePositions<T>(
  FugueTree<T> tree,
  Iterable<FugueElementID> ids,
) {
  final places = <int>{};
  for (final id in ids) {
    if (!tree.isLive(id)) {
      continue;
    }
    final after = tree.liveIndexAfter(id);
    if (after != null) {
      places.add(after - 1);
    }
  }
  return places.toList()..sort();
}

/// A delta that takes out the elements at [places], one step per run of
/// neighbours.
///
/// [places] must be ascending and free of repeats, which is what
/// [fugueLivePositions] hands back.
SequenceDelta<T> fugueDeleteDelta<T>(List<int> places) {
  final ops = <SeqOp<T>>[];
  var cursor = 0;
  var index = 0;

  while (index < places.length) {
    final start = places[index];
    var end = start;
    while (index + 1 < places.length && places[index + 1] == end + 1) {
      index++;
      end = places[index];
    }
    index++;

    if (start > cursor) {
      ops.add(SeqRetain<T>(start - cursor));
    }
    ops.add(SeqDelete<T>(end - start + 1));
    cursor = end + 1;
  }

  return SequenceDelta<T>(ops);
}

/// A delta that swaps the value of the elements [winners] hold.
///
/// An update keeps the element in its slot, so nothing after it moves; the
/// places therefore all belong to one coordinate system and can be read after
/// the whole operation went through.
SequenceDelta<T> fugueUpdateDelta<T>(
  FugueTree<T> tree,
  List<(FugueElementID, T)> winners,
) {
  final entries = <(int, T)>[];
  for (final winner in winners) {
    final after = tree.liveIndexAfter(winner.$1);
    if (after != null) {
      entries.add((after - 1, winner.$2));
    }
  }
  return fugueReplaceDelta<T>(entries);
}

/// A delta that swaps the value held at each place of [entries].
///
/// The places all belong to one coordinate system, because swapping a value
/// moves nothing.
SequenceDelta<T> fugueReplaceDelta<T>(List<(int, T)> entries) {
  entries.sort((a, b) => a.$1.compareTo(b.$1));

  final ops = <SeqOp<T>>[];
  var cursor = 0;
  for (final entry in entries) {
    if (entry.$1 > cursor) {
      ops.add(SeqRetain<T>(entry.$1 - cursor));
    }
    ops
      ..add(SeqDelete<T>(1))
      ..add(SeqInsert<T>([entry.$2]));
    cursor = entry.$1 + 1;
  }

  return SequenceDelta<T>(ops);
}

/// A delta that puts [values] in at [at].
SequenceDelta<T> fugueInsertAtDelta<T>(int at, List<T> values) {
  if (values.isEmpty || at < 0) {
    return SequenceDelta<T>.empty();
  }
  return SequenceDelta<T>([
    if (at > 0) SeqRetain<T>(at),
    SeqInsert<T>(values),
  ]);
}
