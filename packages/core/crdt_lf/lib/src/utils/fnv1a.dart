/// The FNV-1a 32-bit starting value.
const int fnv1a32Offset = 0x811C9DC5;

/// The FNV-1a 32-bit multiplier.
const int _fnv1a32Prime = 0x01000193;

/// Whether this build compiles to JavaScript, where an `int` is a double and
/// a product past 2^53 silently loses precision.
///
/// A compile-time constant, so each build keeps one arm of [fnv1a32] and drops
/// the other.
const bool _isWeb = identical(0, 0.0);

/// FNV-1a 32-bit hash of [bytes] in the range `[start, end)`.
///
/// Pass the result of a previous call as [seed] to hash several buffers into
/// one value, as [Object.hash] would for fields. [end] defaults to the length
/// of [bytes].
///
/// Chosen over [Object.hashAll] because it takes a range without allocating a
/// sub-view, which keeps `hashCode` on packed 24-byte ids allocation-free.
int fnv1a32(
  List<int> bytes, {
  int seed = fnv1a32Offset,
  int start = 0,
  int? end,
}) {
  final last = end ?? bytes.length;
  var hash = seed;

  if (_isWeb) {
    // `hash * prime` reaches ~7.2e16, past the 2^53 a JavaScript number holds
    // exactly, so the product would be rounded before the mask and the result
    // would not be FNV-1a at all. Multiplying the two halves apart keeps every
    // intermediate under 2^41. It costs about twice as much, which is why the
    // native path below stays a single multiply.
    for (var i = start; i < last; i += 1) {
      hash ^= bytes[i];
      final low = hash & 0xFFFF;
      final high = hash >> 16;
      hash = (low * _fnv1a32Prime +
              (((high * _fnv1a32Prime) & 0xFFFF) << 16)) &
          0xFFFFFFFF;
    }
    return hash;
  }

  for (var i = start; i < last; i += 1) {
    hash ^= bytes[i];
    hash = (hash * _fnv1a32Prime) & 0xFFFFFFFF;
  }
  return hash;
}
