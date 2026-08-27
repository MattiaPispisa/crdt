import 'dart:math' as math;

/// The exclusive upper bound on a run length, set by how the two counts are
/// packed into one int.
///
/// A run of a million elements is far past anything the callers build, and
/// `length * _runLimit + liveLength` stays under 2^40 — exact on the web too,
/// where an int is a float64 and only 53 bits are safe.
const int _runLimit = 1 << 20;

/// The `length` and `liveLength` of one key, in a single int.
int _pack(int length, int liveLength) {
  assert(
    length >= 0 && length < _runLimit,
    'run length $length outside 0..$_runLimit',
  );
  assert(
    liveLength >= 0 && liveLength <= length,
    'live length $liveLength outside 0..$length',
  );
  return length * _runLimit + liveLength;
}

int _lengthOf(int packed) => packed ~/ _runLimit;

int _liveLengthOf(int packed) => packed % _runLimit;

/// A single bucket of the [SqrtDecomposition].
///
/// Holds a contiguous slice of the sequence: the [keys], the packed
/// length/live-length pair of each of them ([packed], a parallel list), and
/// the cached sums over the slice ([totalLength] and [totalLiveLength]) so that
/// order-statistic queries can skip whole blocks.
class _Block<T> {
  final List<T> keys = [];

  /// The two counts of each key, packed by [_pack].
  ///
  /// One list rather than two, because an insertion in the middle of a block
  /// shifts every slot after it: a third parallel list cost ~30% on
  /// prepend-heavy building, and nothing on append, which is exactly the shape
  /// of one more shift.
  final List<int> packed = [];

  int totalLength = 0;
  int totalLiveLength = 0;

  /// Recomputes [totalLength] and [totalLiveLength] from [packed].
  ///
  /// Both are kept up to date by hand on every path that changes them; this
  /// is for the one path that rewrites a whole slice, a block split.
  void resum() {
    var total = 0;
    var live = 0;
    for (var i = 0; i < packed.length; i++) {
      total += _lengthOf(packed[i]);
      live += _liveLengthOf(packed[i]);
    }
    totalLength = total;
    totalLiveLength = live;
  }

  /// The offset of [key] inside [keys].
  ///
  /// Sequences are usually built by appending, and neighbour queries usually
  /// land on an edge, so the two ends are checked before the linear scan.
  int offsetOf(T key) {
    final last = keys.length - 1;
    if (last < 0) {
      return -1;
    }
    if (identical(keys[last], key) || keys[last] == key) {
      return last;
    }
    if (identical(keys[0], key) || keys[0] == key) {
      return 0;
    }
    return keys.indexOf(key);
  }
}

/// Order-statistics positional index backed by **square-root decomposition**.
///
/// Square-root decomposition is a classic technique that splits a sequence of
/// `N` entries into ~`√N` contiguous blocks, each caching an aggregate. Queries
/// and updates touch at most one block plus the block list, so every operation
/// is `O(√N)` — a large win over the `O(N)` linear scan while staying far
/// simpler to implement correctly than a balanced order-statistics tree (no
/// rotations, no parent pointers, fully deterministic).
///
/// Reference: [cp-algorithms — Sqrt Decomposition](https://cp-algorithms.com/data_structures/sqrt_decomposition.html).
///
/// ## Keys stand for runs, not for single elements
///
/// Each key carries a **length** (how many elements it stands for) and a **live
/// length** (how many of them are still in the sequence). A key of length one
/// is a single element; a longer one is a *run*, a stretch of elements the
/// caller keeps together. Order statistics are computed over the live subset,
/// while every element — live or not — keeps a stable place in the sequence, so
/// neighbours stay resolvable. This matches a CRDT sequence where deletions are
/// tombstones: a removed element keeps its slot instead of leaving.
///
/// The index knows the two counts and nothing else. **Which** elements inside a
/// run are live is the caller's business, so [liveAt] answers with the run plus
/// how many live elements to walk past inside it, and [liveRankOfRunStart]
/// stops at the run's first element. The caller finishes the descent.
///
/// Because keys are never removed (a deletion only lowers a live length),
/// blocks only grow and split — no merge logic is required, and the block-size
/// target only ever grows.
///
/// `T` is the key type; it must implement `==`/`hashCode`.
class SqrtDecomposition<T> {
  final List<_Block<T>> _blocks = [];
  final Map<T, _Block<T>> _blockOf = {};
  int _runs = 0;
  int _total = 0;
  int _live = 0;

  /// Target block size, ≈ √(number of keys). Monotonically non-decreasing
  /// because [_runs] only grows (keys are never removed).
  int get _target {
    final t = math.sqrt(_runs).ceil();
    return t < 1 ? 1 : t;
  }

  /// The number of keys, i.e. of runs.
  int get runCount => _runs;

  /// The number of elements (live and deleted) the keys stand for.
  int get length => _total;

  /// The number of **live** elements, in `O(1)`.
  ///
  /// Every block caches its own `totalLiveLength`; this is the running sum of
  /// those, so the answer costs no walk over the blocks or over the sequence.
  int get liveLength => _live;

  /// Whether [key] is already present.
  bool contains(T key) => _blockOf.containsKey(key);

  /// How many elements [key] stands for, or `-1` if it is absent.
  int lengthOf(T key) {
    final block = _blockOf[key];
    if (block == null) {
      return -1;
    }
    return _lengthOf(block.packed[block.offsetOf(key)]);
  }

  /// How many live elements [key] stands for, or `-1` if it is absent.
  int liveLengthOf(T key) {
    final block = _blockOf[key];
    if (block == null) {
      return -1;
    }
    return _liveLengthOf(block.packed[block.offsetOf(key)]);
  }

  /// Inserts [key] immediately after [predecessor].
  ///
  /// [predecessor] must already be present.
  void insertAfter(
    T predecessor,
    T key, {
    required int length,
    required int liveLength,
  }) {
    final block = _blockOf[predecessor];
    assert(block != null, 'predecessor must be present');
    if (block == null) {
      return;
    }
    final offset = block.offsetOf(predecessor);
    _insertInto(block, offset + 1, key, length, liveLength);
    _maybeSplit(block);
  }

  /// Inserts [key] at the very front of the sequence.
  void insertAtFront(T key, {required int length, required int liveLength}) {
    if (_blocks.isEmpty) {
      _blocks.add(_Block<T>());
    }
    final block = _blocks.first;
    _insertInto(block, 0, key, length, liveLength);
    _maybeSplit(block);
  }

  void _insertInto(
    _Block<T> block,
    int at,
    T key,
    int length,
    int liveLength,
  ) {
    block
      ..keys.insert(at, key)
      ..packed.insert(at, _pack(length, liveLength))
      ..totalLength += length
      ..totalLiveLength += liveLength;
    _blockOf[key] = block;
    _runs++;
    _total += length;
    _live += liveLength;
  }

  /// Sets how many elements [key] stands for, and how many of them are live.
  ///
  /// This is the one mutator behind every shape change of a run: growing it,
  /// splitting off its tail, or taking some of its elements out of the
  /// sequence. No-op if [key] is absent.
  void setLengths(T key, {required int length, required int liveLength}) {
    final block = _blockOf[key];
    if (block == null) {
      return;
    }
    final offset = block.offsetOf(key);
    final previous = block.packed[offset];
    final lengthDelta = length - _lengthOf(previous);
    final liveDelta = liveLength - _liveLengthOf(previous);
    block
      ..packed[offset] = _pack(length, liveLength)
      ..totalLength += lengthDelta
      ..totalLiveLength += liveDelta;
    _total += lengthDelta;
    _live += liveDelta;
  }

  /// The run holding the [position]-th **live** element, and how many live
  /// elements of that run come before it.
  ///
  /// `null` if [position] is negative or past the last live element. A
  /// `liveOffset` of `0` means the run's first live element; it counts live
  /// elements, not slots, so the caller resolves it against the run's own
  /// liveness.
  ({T key, int liveOffset})? liveAt(int position) {
    if (position < 0) {
      return null;
    }
    var remaining = position;
    for (final block in _blocks) {
      if (remaining >= block.totalLiveLength) {
        remaining -= block.totalLiveLength;
        continue;
      }
      for (var i = 0; i < block.keys.length; i++) {
        final live = _liveLengthOf(block.packed[i]);
        if (remaining < live) {
          return (key: block.keys[i], liveOffset: remaining);
        }
        remaining -= live;
      }
    }
    return null;
  }

  /// The number of live elements strictly before the run [key] opens, or `-1`
  /// if [key] is absent.
  ///
  /// Elements of the run itself are not counted, whichever of them are live:
  /// the caller adds what it knows about the inside of the run.
  int liveRankOfRunStart(T key) {
    final block = _blockOf[key];
    if (block == null) {
      return -1;
    }
    var rank = 0;
    for (final candidate in _blocks) {
      if (identical(candidate, block)) {
        break;
      }
      rank += candidate.totalLiveLength;
    }
    final offset = block.offsetOf(key);
    for (var i = 0; i < offset; i++) {
      rank += _liveLengthOf(block.packed[i]);
    }
    return rank;
  }

  /// Returns the key immediately before [key], or `null` if [key] is first
  /// (or absent).
  T? predecessorOf(T key) {
    final block = _blockOf[key];
    if (block == null) {
      return null;
    }
    final offset = block.offsetOf(key);
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

  /// Returns the key immediately after [key], or `null` if [key] is last
  /// (or absent).
  T? successorOf(T key) {
    final block = _blockOf[key];
    if (block == null) {
      return null;
    }
    final offset = block.offsetOf(key);
    if (offset < block.keys.length - 1) {
      return block.keys[offset + 1];
    }
    var seen = false;
    for (final candidate in _blocks) {
      if (seen && candidate.keys.isNotEmpty) {
        return candidate.keys.first;
      }
      if (identical(candidate, block)) {
        seen = true;
      }
    }
    return null;
  }

  /// Calls [action] on every run that holds at least one live element, in
  /// sequence order.
  ///
  /// Blocks with no live element are skipped whole, so a sequence that is
  /// mostly tombstones costs far less than one pass per run.
  void forEachLiveRun(
    void Function(T key, int length, int liveLength) action,
  ) {
    for (final block in _blocks) {
      if (block.totalLiveLength == 0) {
        continue;
      }
      for (var i = 0; i < block.keys.length; i++) {
        final entry = block.packed[i];
        final live = _liveLengthOf(entry);
        if (live > 0) {
          action(block.keys[i], _lengthOf(entry), live);
        }
      }
    }
  }

  /// Calls [action] on every run, live or not, in sequence order.
  ///
  /// The index holds the whole sequence: keys only ever change how much they
  /// stand for, they never leave. Use [forEachLiveRun] when the dead ones do
  /// not matter — it skips them a block at a time, which this cannot.
  void forEachRun(void Function(T key, int length, int liveLength) action) {
    for (final block in _blocks) {
      for (var i = 0; i < block.keys.length; i++) {
        final entry = block.packed[i];
        action(block.keys[i], _lengthOf(entry), _liveLengthOf(entry));
      }
    }
  }

  /// Walks runs in sequence order, starting at the one [liveAt] would return
  /// for [position].
  ///
  /// The first run comes with the `liveOffset` to start from, the ones after it
  /// with `0`. [action] returns `false` to stop the walk. Nothing happens for a
  /// negative [position] or one past the last live element.
  ///
  /// Finding the start costs `O(√N)` once and the rest is a scan, so a caller
  /// reading a stretch of the sequence pays far less than one [liveAt] per
  /// element.
  void forEachRunFromLive(
    int position,
    bool Function(T key, int length, int liveLength, int liveOffset) action,
  ) {
    if (position < 0) {
      return;
    }
    var remaining = position;
    var started = false;
    for (final block in _blocks) {
      if (!started && remaining >= block.totalLiveLength) {
        remaining -= block.totalLiveLength;
        continue;
      }
      for (var i = 0; i < block.keys.length; i++) {
        final entry = block.packed[i];
        final live = _liveLengthOf(entry);
        if (!started) {
          if (remaining >= live) {
            remaining -= live;
            continue;
          }
          started = true;
          if (!action(block.keys[i], _lengthOf(entry), live, remaining)) {
            return;
          }
          continue;
        }
        if (!action(block.keys[i], _lengthOf(entry), live, 0)) {
          return;
        }
      }
    }
  }

  /// Returns the first key in the sequence, or `null` if empty.
  T? first() {
    for (final block in _blocks) {
      if (block.keys.isNotEmpty) {
        return block.keys.first;
      }
    }
    return null;
  }

  /// Returns the last key in the sequence, or `null` if empty.
  T? last() {
    if (_blocks.isEmpty) {
      return null;
    }
    final block = _blocks.last;
    return block.keys.isEmpty ? null : block.keys.last;
  }

  /// Rebuilds the index in `O(n)` from an already-ordered sequence.
  ///
  /// [keys], [lengths] and [liveLengths] are parallel lists in sequence order.
  void bulkBuild(List<T> keys, List<int> lengths, List<int> liveLengths) {
    clear();
    _runs = keys.length;
    if (keys.isEmpty) {
      return;
    }
    final target = math.sqrt(keys.length).ceil().clamp(1, keys.length);
    for (var start = 0; start < keys.length; start += target) {
      final end = (start + target < keys.length) ? start + target : keys.length;
      final block = _Block<T>();
      for (var i = start; i < end; i++) {
        block
          ..keys.add(keys[i])
          ..packed.add(_pack(lengths[i], liveLengths[i]))
          ..totalLength += lengths[i]
          ..totalLiveLength += liveLengths[i];
        _total += lengths[i];
        _live += liveLengths[i];
        _blockOf[keys[i]] = block;
      }
      _blocks.add(block);
    }
  }

  /// Empties the index.
  void clear() {
    _blocks.clear();
    _blockOf.clear();
    _runs = 0;
    _total = 0;
    _live = 0;
  }

  /// Splits [block] in half when it grows past `2 * target`, keeping block
  /// sizes within `[target/2, 2*target]` and the block count ≈ √(runs).
  void _maybeSplit(_Block<T> block) {
    final target = _target;
    if (block.keys.length <= 2 * target) {
      return;
    }
    final index = _blocks.indexOf(block);
    final mid = block.keys.length ~/ 2;

    final right = _Block<T>()
      ..keys.addAll(block.keys.sublist(mid))
      ..packed.addAll(block.packed.sublist(mid))
      ..resum();

    block
      ..keys.removeRange(mid, block.keys.length)
      ..packed.removeRange(mid, block.packed.length)
      ..resum();

    for (final key in right.keys) {
      _blockOf[key] = right;
    }
    _blocks.insert(index + 1, right);
  }
}
