// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

/// Whether [a] and [b] hold the same keys with equal values, in any order.
bool sameAttributes(Map<String, Object?> a, Map<String, Object?> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
