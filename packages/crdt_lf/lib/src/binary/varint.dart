import 'dart:typed_data';

/// Result of decoding an unsigned varint.
class UVarintResult {
  /// Create a [UVarintResult] instance
  /// for the given [value] and [nextOffset].
  const UVarintResult(this.value, this.nextOffset);

  /// The decoded integer value.
  final int value;

  /// The offset immediately after the decoded varint.
  final int nextOffset;
}

/// Unsigned Varint encoding utilities.
///
/// This codec implements base-128 varints (LEB128-style)
/// for non-negative integers.
/// It is optimized for compact representation of small numbers.
class UVarint {
  UVarint._();

  /// Encodes [value] as an unsigned varint and appends it to [out].
  ///
  /// Throws an [ArgumentError] if [value] is negative.
  static void write(int value, BytesBuilder out) {
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'Must be non-negative');
    }

    var v = value;

    // While the value is greater than or equal to 128 (0x80),
    // it requires more than 7 bits to represent.
    while (v >= 0x80) {
      // Write the lowest 7 bits of the current value.
      // We set the 8th bit (0x80) to 1 to indicate more bytes follow.
      // Note: The bitwise AND (v & 0x7F) is safe on Web because
      // it only operates on the lower 7 bits.
      out.addByte((v & 0x7F) | 0x80);

      // Divide by 128 to shift right by 7 bits.
      // We use .floor() because division in JavaScript results in a float.
      // This arithmetic approach is safe for large integers on the Web.
      v = (v / 128).floor();
    }

    // Write the last byte (continuation bit is 0).
    out.addByte(v);
  }

  /// Decodes an unsigned varint from [bytes], starting at [offset].
  ///
  /// Returns a [UVarintResult] containing the decoded value and the new offset.
  /// Throws a [FormatException] if the varint is truncated or invalid.
  static UVarintResult read(
    Uint8List bytes, {
    required int offset,
  }) {
    var result = 0;
    var multiplier = 1;
    var i = offset;

    while (i < bytes.length) {
      final b = bytes[i];

      // Extract the 7 bits of data from the current byte.
      final val = b & 0x7F;

      // Accumulate the result using arithmetic multiplication.
      // This avoids the 32-bit limit of bitwise shifts on the Web.
      result += val * multiplier;

      i++;

      // If the continuation bit (0x80) is not set, this is the last byte.
      if ((b & 0x80) == 0) {
        return UVarintResult(result, i);
      }

      // Prepare the multiplier for the next 7 bits (equivalent to << 7).
      multiplier *= 128;
    }

    throw const FormatException('Truncated varint: end of buffer reached');
  }
}
