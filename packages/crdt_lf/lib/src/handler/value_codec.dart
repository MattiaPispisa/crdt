import 'dart:convert';
import 'dart:typed_data';

/// Codec for encoding/decoding generic values into bytes.
abstract class ValueCodec<T> {
  /// Encodes [value] into bytes.
  Uint8List encode(T value);

  /// Decodes [bytes] into a value.
  T decode(Uint8List bytes);
}

/// Default JSON-based value codec.
///
/// This uses `utf8(jsonEncode(value))` and `jsonDecode`.
/// It is intended as a safe default for common JSON-compatible values.
class JsonValueCodec<T> implements ValueCodec<T> {
  /// Creates a new [JsonValueCodec] instance.
  const JsonValueCodec();

  @override
  Uint8List encode(T value) {
    final s = jsonEncode(value);
    return Uint8List.fromList(utf8.encode(s));
  }

  @override
  T decode(Uint8List bytes) {
    final s = utf8.decode(bytes);
    final v = jsonDecode(s);
    return v as T;
  }
}
