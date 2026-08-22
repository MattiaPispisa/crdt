import 'dart:typed_data';

/// WTF-8 (Wobbly Transformation Format 8-bit) codec.
///
/// See <https://simonsapin.github.io/wtf-8/> for the reference definition.
class Wtf8 {
  /// Encodes [input] to WTF-8 bytes.
  ///
  /// Valid surrogate pairs are combined into a single supplementary code point
  /// (identical to UTF-8); lone surrogates are preserved as 3-byte sequences.
  static Uint8List encode(String input) {
    final out = BytesBuilder(copy: false);
    _encodeInto(input, out);
    return out.toBytes();
  }

  /// Appends the WTF-8 form of [input] to [out].
  static void _encodeInto(String input, BytesBuilder out) {
    final units = input.codeUnits;
    final len = units.length;
    var i = 0;
    while (i < len) {
      final unit = units[i];
      int codePoint;
      if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < len) {
        final next = units[i + 1];
        if (next >= 0xDC00 && next <= 0xDFFF) {
          // Valid surrogate pair -> supplementary code point (4-byte in UTF-8).
          codePoint = 0x10000 + ((unit - 0xD800) << 10) + (next - 0xDC00);
          i += 2;
        } else {
          // Lone high surrogate.
          codePoint = unit;
          i += 1;
        }
      } else {
        // BMP scalar, or a lone surrogate (high without a following low, or a
        // low surrogate).
        codePoint = unit;
        i += 1;
      }
      _writeCodePoint(codePoint, out);
    }
  }

  /// Encodes every value of [values] on its own and concatenates the result.
  ///
  /// Not the same as encoding `values.join()`: a lone high surrogate followed
  /// by a lone low surrogate would pair up there into a single 4-byte
  /// sequence, and the two would come back as one. Encoding value by value
  /// keeps one sequence per value, which is what makes [decodeCodePoints] the
  /// exact inverse for values of one code point each.
  static Uint8List encodeAll(Iterable<String> values) {
    final out = BytesBuilder(copy: false);
    for (final value in values) {
      _encodeInto(value, out);
    }
    return out.toBytes();
  }

  /// Decodes WTF-8 [bytes] into one string per encoded code point.
  ///
  /// Splits on the byte sequences rather than re-scanning the decoded string:
  /// `String.runes` pairs two adjacent lone surrogates back into one code
  /// point, which would merge two values into one.
  ///
  /// Throws a [FormatException] if a multi-byte sequence is truncated.
  static List<String> decodeCodePoints(Uint8List bytes) {
    final result = <String>[];
    final len = bytes.length;
    var start = 0;
    while (start < len) {
      final end = _sequenceEnd(bytes, start);
      result.add(decode(Uint8List.sublistView(bytes, start, end)));
      start = end;
    }
    return result;
  }

  /// The offset just past the WTF-8 sequence that starts at [start].
  static int _sequenceEnd(Uint8List bytes, int start) {
    final b0 = bytes[start];
    final int width;
    if (b0 < 0x80) {
      width = 1;
    } else if (b0 < 0xE0) {
      width = 2;
    } else if (b0 < 0xF0) {
      width = 3;
    } else {
      width = 4;
    }
    if (start + width > bytes.length) {
      throw const FormatException('Truncated WTF-8 sequence');
    }
    return start + width;
  }

  /// Decodes WTF-8 [bytes] back to a [String].
  ///
  /// Throws a [FormatException] if a multi-byte sequence is truncated.
  static String decode(Uint8List bytes) {
    final units = <int>[];
    final len = bytes.length;
    var i = 0;
    while (i < len) {
      final b0 = bytes[i];
      if (b0 < 0x80) {
        units.add(b0);
        i += 1;
      } else if (b0 < 0xE0) {
        if (i + 1 >= len) {
          throw const FormatException('Truncated WTF-8 sequence');
        }
        units.add(((b0 & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
        i += 2;
      } else if (b0 < 0xF0) {
        // 3-byte sequence: may encode a lone surrogate (U+D800–U+DFFF), which
        // WTF-8 permits and we keep as a single code unit.
        if (i + 2 >= len) {
          throw const FormatException('Truncated WTF-8 sequence');
        }
        units.add(
          ((b0 & 0x0F) << 12) |
              ((bytes[i + 1] & 0x3F) << 6) |
              (bytes[i + 2] & 0x3F),
        );
        i += 3;
      } else {
        // 4-byte sequence -> supplementary code point -> surrogate pair.
        if (i + 3 >= len) {
          throw const FormatException('Truncated WTF-8 sequence');
        }
        final cp = ((b0 & 0x07) << 18) |
            ((bytes[i + 1] & 0x3F) << 12) |
            ((bytes[i + 2] & 0x3F) << 6) |
            (bytes[i + 3] & 0x3F);
        final v = cp - 0x10000;
        units
          ..add(0xD800 + (v >> 10))
          ..add(0xDC00 + (v & 0x3FF));
        i += 4;
      }
    }
    return String.fromCharCodes(units);
  }

  static void _writeCodePoint(int cp, BytesBuilder out) {
    if (cp <= 0x7F) {
      out.addByte(cp);
    } else if (cp <= 0x7FF) {
      out
        ..addByte(0xC0 | (cp >> 6))
        ..addByte(0x80 | (cp & 0x3F));
    } else if (cp <= 0xFFFF) {
      out
        ..addByte(0xE0 | (cp >> 12))
        ..addByte(0x80 | ((cp >> 6) & 0x3F))
        ..addByte(0x80 | (cp & 0x3F));
    } else {
      out
        ..addByte(0xF0 | (cp >> 18))
        ..addByte(0x80 | ((cp >> 12) & 0x3F))
        ..addByte(0x80 | ((cp >> 6) & 0x3F))
        ..addByte(0x80 | (cp & 0x3F));
    }
  }
}
