import 'package:crdt_lf/src/delta/handler_update.dart';

/// What happened to one key of a map.
sealed class MapEntryChange<T> {
  /// Creates an entry change.
  const MapEntryChange();
}

/// The key now holds [value].
final class MapEntrySet<T> extends MapEntryChange<T> {
  /// The key was written with [value], replacing [previous].
  const MapEntrySet({required this.value, required this.previous});

  /// What the key holds now.
  final T value;

  /// What the key held before, or `null` when the key was absent.
  ///
  /// For a map of a nullable type those two cases both read as `null` here,
  /// and nothing in the delta tells them apart. It costs nothing: [value] is
  /// what the key holds now, so [MapDelta.apply] is right either way. Only a
  /// consumer that shows "what it used to be" is affected.
  final T? previous;

  @override
  bool operator ==(Object other) =>
      other is MapEntrySet<T> &&
      other.value == value &&
      other.previous == previous;

  @override
  int get hashCode => Object.hash(MapEntrySet<T>, value, previous);

  @override
  String toString() => 'MapEntrySet($previous -> $value)';
}

/// The key is gone.
final class MapEntryRemoved<T> extends MapEntryChange<T> {
  /// The key was removed, dropping [previous].
  const MapEntryRemoved({required this.previous});

  /// What the key held before it was removed.
  final T previous;

  @override
  bool operator ==(Object other) =>
      other is MapEntryRemoved<T> && other.previous == previous;

  @override
  int get hashCode => Object.hash(MapEntryRemoved<T>, previous);

  @override
  String toString() => 'MapEntryRemoved($previous)';
}

/// How a map handler's value moved, as one entry per touched key.
///
/// A key that did not move is absent. An operation with no observable effect —
/// updating a key that is not there — produces an empty delta, not a phantom
/// entry.
final class MapDelta<K, V> implements ComposableDelta<MapDelta<K, V>> {
  /// Creates a delta from [entries].
  const MapDelta(this.entries);

  /// The delta that moves nothing.
  const MapDelta.empty() : entries = const {};

  /// The touched keys.
  final Map<K, MapEntryChange<V>> entries;

  /// Whether this delta moves nothing.
  bool get isEmpty => entries.isEmpty;

  /// Whether this delta moves something.
  bool get isNotEmpty => entries.isNotEmpty;

  /// The delta that has the same effect as this one followed by [next].
  ///
  /// A key touched by both keeps the value [next] wrote and the value this
  /// delta started from, so the pair still describes the whole move.
  @override
  MapDelta<K, V> compose(MapDelta<K, V> next) {
    final merged = Map<K, MapEntryChange<V>>.of(entries);

    for (final entry in next.entries.entries) {
      final mine = merged[entry.key];
      final theirs = entry.value;

      if (mine == null) {
        merged[entry.key] = theirs;
        continue;
      }

      // The starting point is the one this delta already recorded.
      final origin = switch (mine) {
        MapEntrySet<V>() => mine.previous,
        MapEntryRemoved<V>() => mine.previous,
      };

      switch (theirs) {
        case final MapEntrySet<V> change:
          merged[entry.key] =
              MapEntrySet<V>(value: change.value, previous: origin);
        case MapEntryRemoved<V>():
          if (origin == null) {
            // Put in and taken out again: the key never existed.
            merged.remove(entry.key);
          } else {
            merged[entry.key] = MapEntryRemoved<V>(previous: origin);
          }
      }
    }

    return MapDelta<K, V>(merged);
  }

  /// The map [base] becomes once this delta is applied.
  ///
  /// [base] is left alone; the result is a new map.
  Map<K, V> apply(Map<K, V> base) {
    final result = Map<K, V>.of(base);
    for (final entry in entries.entries) {
      switch (entry.value) {
        case final MapEntrySet<V> change:
          result[entry.key] = change.value;
        case MapEntryRemoved<V>():
          result.remove(entry.key);
      }
    }
    return result;
  }

  @override
  bool operator ==(Object other) {
    if (other is! MapDelta<K, V> || other.entries.length != entries.length) {
      return false;
    }
    for (final entry in entries.entries) {
      if (other.entries[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
        entries.entries.map((e) => Object.hash(e.key, e.value)),
      );

  @override
  String toString() => 'MapDelta($entries)';
}
