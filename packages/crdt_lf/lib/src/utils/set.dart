/// Checks if two sets are equal
///
/// ```dart
/// final set1 = {1, 2, 3};
/// final set2 = {1, 2, 3};
/// print(setEquals(set1, set2)); // Prints true
///
/// final set3 = {1, 2, 4};
/// print(setEquals(set1, set3)); // Prints false
/// ```
bool setEquals<T>(Set<T>? a, Set<T>? b) {
  if (a == null) {
    return b == null;
  }
  if (b == null || a.length != b.length) {
    return false;
  }
  return a.containsAll(b);
}
