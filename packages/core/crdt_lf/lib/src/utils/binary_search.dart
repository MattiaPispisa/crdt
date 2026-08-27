/// Binary-search helpers for sorted [List]s.
extension BinarySearchList<E> on List<E> {
  /// The leftmost index in `[start, end)` whose element does not compare
  /// less than [target] under [compare]. Returns `end` (default: [length])
  /// if every element compares less than [target].
  ///
  /// This list must already be sorted by [compare] over that range.
  int lowerBoundBy<T>(
    T target,
    int Function(E element, T target) compare, {
    int start = 0,
    int? end,
  }) {
    final validEnd = RangeError.checkValidRange(start, end, length);
    var min = start;
    var max = validEnd;
    while (min < max) {
      final mid = min + ((max - min) >> 1);
      if (compare(this[mid], target) < 0) {
        min = mid + 1;
      } else {
        max = mid;
      }
    }
    return min;
  }
}
