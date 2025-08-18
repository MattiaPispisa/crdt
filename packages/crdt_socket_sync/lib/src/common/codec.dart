import 'dart:convert';

/// Interface for encoding and decoding messages
abstract class MessageCodec<T> {
  /// Encode a message into a format suitable for transport
  List<int>? encode(T message);

  /// Decode a message from the transport format
  T? decode(List<int> data);
}

/// A message codec that uses JSON for serialization.
///
/// This codec allows for custom handling of non-standard JSON types by
/// accepting optional `toEncodable` and `reviver` functions, which are
/// passed directly to `jsonEncode` and `jsonDecode` respectively.
class JsonMessageCodec<T> implements MessageCodec<T> {
  /// Creates a [JsonMessageCodec].
  ///
  /// [toJson] is a function that converts an object of type [T] to a
  /// `Map<String, dynamic>`.
  /// [fromJson] is a function that creates an object of type [T] from a
  /// `Map<String, dynamic>`.
  /// [toEncodable] is an optional function passed to `jsonEncode` to handle
  /// objects that are not directly encodable to JSON.
  /// [reviver] is an optional function passed to `jsonDecode` to transform
  /// decoded values.
  const JsonMessageCodec({
    required Map<String, dynamic>? Function(T) toJson,
    required T? Function(Map<String, dynamic>) fromJson,
    Object? Function(Object? nonEncodable)? toEncodable,
    Object? Function(Object? key, Object? value)? reviver,
  })  : _toJson = toJson,
        _fromJson = fromJson,
        _toEncodable = toEncodable,
        _reviver = reviver;

  final Map<String, dynamic>? Function(T) _toJson;
  final T? Function(Map<String, dynamic>) _fromJson;
  final Object? Function(Object? nonEncodable)? _toEncodable;
  final Object? Function(Object? key, Object? value)? _reviver;

  @override
  List<int>? encode(T message) {
    final json = _toJson(message);
    if (json == null) return null;

    final jsonStr = jsonEncode(json, toEncodable: _toEncodable);
    return utf8.encode(jsonStr);
  }

  @override
  T? decode(List<int> data) {
    final jsonStr = utf8.decode(data);
    final json = jsonDecode(jsonStr, reviver: _reviver) as Map<String, dynamic>;
    return _fromJson(json);
  }
}
