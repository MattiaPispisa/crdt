import 'dart:math' as math;

/// A single bucket of the [SqrtDecomposition].
///
/// Holds a contiguous slice of the sequence: the [keys], their [live] flags
/// (parallel list) and the cached [liveCount] of the slice so that
/// order-statistic queries can skip whole blocks.
class _Block<T> {
  final List<T> keys = [];
  final List<bool> live = [];
  int liveCount = 0;
}

/// Order-statistics positional index backed by **square-root decomposition**.
///
/// Square-root decomposition is a classic technique that splits a sequence of
/// `N` elements into ~`√N` contiguous blocks, each caching an aggregate (here
/// the number of *live* elements). Queries and updates touch at most one block
/// plus the block list, so every operation is `O(√N)` — a large win over the
/// `O(N)` linear scan while staying far simpler to implement correctly than a
/// balanced order-statistics tree (no rotations, no parent pointers, fully
/// deterministic).
///
/// Reference: [cp-algorithms — Sqrt Decomposition](https://cp-algorithms.com/data_structures/sqrt_decomposition.html).
///
/// Each element carries a `live` flag. The order statistic (`liveAt`,
/// `liveRankOf`) is computed over the **live** subset only, while every element
/// — live or not — keeps a stable place in the sequence so neighbors stay
/// resolvable. This matches a CRDT sequence where deletions are tombstones:
/// removed elements keep their slot (`live == false`) instead of leaving.
///
/// Because elements are never removed (deletion only flips a flag), blocks only
/// grow and split — no merge logic is required.
///
/// `T` is the element key type; it must implement `==`/`hashCode`.
class SqrtDecomposition<T> {
  final List<_Block<T>> _blocks = [];
  final Map<T, _Block<T>> _blockOf = {};
  int _total = 0;

  /// Target block size, ≈ √N. Monotonically non-decreasing because [_total]
  /// only grows (elements are never removed).
  int get _target {
    final t = math.sqrt(_total).ceil();
    return t < 1 ? 1 : t;
  }

  /// The number of elements (live and deleted) in the index.
  int get length => _total;

  /// Whether [key] is already present.
  bool contains(T key) => _blockOf.containsKey(key);

  /// Inserts [key] immediately after [predecessor].
  ///
  /// [predecessor] must already be present.
  void insertAfter(T predecessor, T key, {required bool live}) {
    final block = _blockOf[predecessor];
    assert(block != null, 'predecessor must be present');
    if (block == null) {
      return;
    }
    final offset = block.keys.indexOf(predecessor);
    block.keys.insert(offset + 1, key);
    block.live.insert(offset + 1, live);
    if (live) {
      block.liveCount++;
    }
    _blockOf[key] = block;
    _total++;
    _maybeSplit(block);
  }

  /// Inserts [key] at the very front of the sequence.
  void insertAtFront(T key, {required bool live}) {
    if (_blocks.isEmpty) {
      final block = _Block<T>()
        ..keys.add(key)
        ..live.add(live)
        ..liveCount = live ? 1 : 0;
      _blocks.add(block);
      _blockOf[key] = block;
      _total++;
      return;
    }
    final block = _blocks.first;
    block.keys.insert(0, key);
    block.live.insert(0, live);
    if (live) {
      block.liveCount++;
    }
    _blockOf[key] = block;
    _total++;
    _maybeSplit(block);
  }

  /// Sets the `live` flag of [key]. No-op if [key] is absent.
  void setLive(T key, {required bool live}) {
    final block = _blockOf[key];
    if (block == null) {
      return;
    }
    final offset = block.keys.indexOf(key);
    if (block.live[offset] == live) {
      return;
    }
    block.live[offset] = live;
    block.liveCount += live ? 1 : -1;
  }

  /// Returns the [position]-th **live** key, or `null` if [position] is
  /// negative or past the last live element.
  T? liveAt(int position) {
    if (position < 0) {
      return null;
    }
    var remaining = position;
    for (final block in _blocks) {
      if (remaining < block.liveCount) {
        for (var i = 0; i < block.keys.length; i++) {
          if (block.live[i]) {
            if (remaining == 0) {
              return block.keys[i];
            }
            remaining--;
          }
        }
      } else {
        remaining -= block.liveCount;
      }
    }
    return null;
  }

  /// Returns the number of live elements strictly before [key] (its live
  /// index), or `-1` if [key] is absent.
  int liveRankOf(T key) {
    final block = _blockOf[key];
    if (block == null) {
      return -1;
    }
    var rank = 0;
    for (final candidate in _blocks) {
      if (identical(candidate, block)) {
        break;
      }
      rank += candidate.liveCount;
    }
    final offset = block.keys.indexOf(key);
    for (var i = 0; i < offset; i++) {
      if (block.live[i]) {
        rank++;
      }
    }
    return rank;
  }

  /// Returns the element immediately before [key], or `null` if [key] is first
  /// (or absent).
  T? predecessorOf(T key) {
    final block = _blockOf[key];
    if (block == null) {
      return null;
    }
    final offset = block.keys.indexOf(key);
    if (offset > 0) {
      return block.keys[offset - 1];
    }
    _Block<T>? previous;
    for (final candidate in _blocks) {
      if (identical(candidate, block)) {
        break;
      }
      previous = candidate;
    }
    if (previous == null || previous.keys.isEmpty) {
      return null;
    }
    return previous.keys.last;
  }

  /// Returns the last element in the sequence, or `null` if empty.
  T? last() {
    if (_blocks.isEmpty) {
      return null;
    }
    final block = _blocks.last;
    return block.keys.isEmpty ? null : block.keys.last;
  }

  /// Rebuilds the index in `O(n)` from an already-ordered sequence.
  ///
  /// [keys] and [live] are parallel lists in sequence order.
  void bulkBuild(List<T> keys, List<bool> live) {
    clear();
    _total = keys.length;
    if (keys.isEmpty) {
      return;
    }
    final target = math.sqrt(keys.length).ceil().clamp(1, keys.length);
    for (var start = 0; start < keys.length; start += target) {
      final end = (start + target < keys.length) ? start + target : keys.length;
      final block = _Block<T>();
      for (var i = start; i < end; i++) {
        block.keys.add(keys[i]);
        block.live.add(live[i]);
        if (live[i]) {
          block.liveCount++;
        }
        _blockOf[keys[i]] = block;
      }
      _blocks.add(block);
    }
  }

  /// Empties the index.
  void clear() {
    _blocks.clear();
    _blockOf.clear();
    _total = 0;
  }

  /// Splits [block] in half when it grows past `2 * target`, keeping block
  /// sizes within `[target/2, 2*target]` and the block count ≈ √N.
  void _maybeSplit(_Block<T> block) {
    final target = _target;
    if (block.keys.length <= 2 * target) {
      return;
    }
    final index = _blocks.indexOf(block);
    final mid = block.keys.length ~/ 2;

    final right = _Block<T>()
      ..keys.addAll(block.keys.sublist(mid))
      ..live.addAll(block.live.sublist(mid));
    right.liveCount = right.live.where((l) => l).length;

    block.keys.removeRange(mid, block.keys.length);
    block.live.removeRange(mid, block.live.length);
    block.liveCount = block.live.where((l) => l).length;

    for (final key in right.keys) {
      _blockOf[key] = right;
    }
    _blocks.insert(index + 1, right);
  }
}
