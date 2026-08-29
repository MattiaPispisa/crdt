import 'package:crdt_lf/src/delta/handler_update.dart';

/// How a set handler's value moved.
///
/// Membership only. An operation that changes the internal tags of a value
/// without changing whether the value is in the set produces an empty delta.
final class SetDelta<T> implements ComposableDelta<SetDelta<T>> {
  /// Creates a delta from [added] and [removed].
  const SetDelta({required this.added, required this.removed});

  /// The delta that moves nothing.
  const SetDelta.empty()
      : added = const {},
        removed = const {};

  /// The values that are in the set now and were not before.
  final Set<T> added;

  /// The values that were in the set before and are not now.
  final Set<T> removed;

  @override
  bool get isEmpty => added.isEmpty && removed.isEmpty;

  /// Whether this delta moves something.
  bool get isNotEmpty => !isEmpty;

  /// The delta that has the same effect as this one followed by [next].
  ///
  /// A value put in here and taken out by [next] cancels, and the other way
  /// round, so the result never claims a move that did not happen.
  @override
  SetDelta<T> compose(SetDelta<T> next) => SetDelta<T>(
        added: {
          ...added.where((v) => !next.removed.contains(v)),
          ...next.added.where((v) => !removed.contains(v)),
        },
        removed: {
          ...removed.where((v) => !next.added.contains(v)),
          ...next.removed.where((v) => !added.contains(v)),
        },
      );

  /// The set [base] becomes once this delta is applied.
  ///
  /// [base] is left alone; the result is a new set.
  Set<T> apply(Set<T> base) =>
      {...base, ...added}..removeWhere(removed.contains);

  @override
  bool operator ==(Object other) =>
      other is SetDelta<T> &&
      other.added.length == added.length &&
      other.removed.length == removed.length &&
      other.added.containsAll(added) &&
      other.removed.containsAll(removed);

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(added),
        Object.hashAllUnordered(removed),
      );

  @override
  String toString() => 'SetDelta(added: $added, removed: $removed)';
}
