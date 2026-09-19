/// Whether [a] and [b] hold the same bytes.
///
/// `package:collection`'s `ListEquality` does the same job, but it is not a
/// dependency of this package, and it walks an `Iterable`. This indexes the
/// lists directly, which matters on the change apply path.
bool bytesEqual(List<int> a, List<int> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// Whether [data] starts with every byte of [prefix].
///
/// A [prefix] longer than [data] is not a prefix, so this returns `false`.
/// An empty [prefix] is a prefix of anything.
bool startsWithBytes(List<int> data, List<int> prefix) {
  if (prefix.length > data.length) {
    return false;
  }
  for (var i = 0; i < prefix.length; i += 1) {
    if (data[i] != prefix[i]) {
      return false;
    }
  }
  return true;
}

/// Whether [data] holds every byte of [bytes] starting at [offset].
///
/// Lets a caller match a slice of a buffer without copying it out first, which
/// is what keeps a comparison on the change apply path free of allocation.
bool bytesEqualAt(List<int> data, int offset, List<int> bytes) {
  if (offset < 0 || offset + bytes.length > data.length) {
    return false;
  }
  for (var i = 0; i < bytes.length; i += 1) {
    if (data[offset + i] != bytes[i]) {
      return false;
    }
  }
  return true;
}
