// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

/// [offset] moved back to the start of a surrogate pair it points into.
int runeBoundary(String text, int offset) {
  if (offset <= 0 || offset >= text.length) {
    return offset.clamp(0, text.length);
  }
  final unit = text.codeUnitAt(offset);
  return (unit >= 0xDC00 && unit <= 0xDFFF) ? offset - 1 : offset;
}

/// The offset after the rune that starts at [at].
int nextRune(String text, int at) {
  final unit = text.codeUnitAt(at);
  return (unit >= 0xD800 && unit <= 0xDBFF && at + 1 < text.length)
      ? at + 2
      : at + 1;
}
