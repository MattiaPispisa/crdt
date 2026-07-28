/// Conversions between UTF-16 code unit and runes.
class RuneOffsets {
  /// Number of runes in [text].
  ///
  /// Equivalent to `text.runes.length` **without materializing the iterator**.
  static int length(String text) {
    final length = text.length;
    var runes = 0;
    var i = 0;
    while (i < length) {
      i += _runeWidthAt(text, i, length);
      runes++;
    }
    return runes;
  }

  /// UTF-16 code-unit offset at which the rune numbered [runeIndex] starts.
  ///
  /// Out-of-range indices clamp to the ends of [text].
  ///
  /// ```dart
  /// // 'a😀b' is 4 code units but 3 runes: the emoji spans offsets 1-2.
  /// print(RuneOffsets.utf16Offset('a😀b', 1)); // Prints 1 (the emoji)
  /// print(RuneOffsets.utf16Offset('a😀b', 2)); // Prints 3 (the 'b')
  /// print(RuneOffsets.utf16Offset('a😀b', 9)); // Prints 4 (clamped)
  /// ```
  static int utf16Offset(String text, int runeIndex) {
    if (runeIndex <= 0) {
      return 0;
    }
    final length = text.length;
    var offset = 0;
    var runes = 0;
    while (offset < length && runes < runeIndex) {
      offset += _runeWidthAt(text, offset, length);
      runes++;
    }
    return offset;
  }

  /// Index of the rune that starts at [utf16Offset].
  ///
  /// ```dart
  /// print(RuneOffsets.runeIndex('a😀b', 1)); // Prints 1 (the emoji)
  /// print(RuneOffsets.runeIndex('a😀b', 3)); // Prints 2 (the 'b')
  /// print(RuneOffsets.runeIndex('a😀b', 2)); // Prints 1 (inside the emoji)
  /// print(RuneOffsets.runeIndex('a😀b', 9)); // Prints 3 (clamped)
  /// ```
  static int runeIndex(String text, int utf16Offset) {
    if (utf16Offset <= 0) {
      return 0;
    }
    final length = text.length;
    var offset = 0;
    var runes = 0;
    while (offset < length) {
      final width = _runeWidthAt(text, offset, length);
      if (offset + width > utf16Offset) {
        break;
      }
      offset += width;
      runes++;
    }
    return runes;
  }

  /// Code units spanned by the rune starting at [offset]: 2 for a well-formed
  /// surrogate pair, 1 otherwise (including an unpaired surrogate).
  static int _runeWidthAt(String text, int offset, int length) {
    final unit = text.codeUnitAt(offset);
    if (unit >= 0xD800 && unit <= 0xDBFF && offset + 1 < length) {
      final next = text.codeUnitAt(offset + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        return 2;
      }
    }
    return 1;
  }
}
