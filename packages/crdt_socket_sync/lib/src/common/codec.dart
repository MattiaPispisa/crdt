import 'dart:convert';

/// Interface for encoding and decoding messages
abstract class MessageCodec<T> {
  /// Encode a message into a format suitable for transport
  List<int>? encode(T message);

  /// Decode a message from the transport format
  T? decode(List<int> data);
}

/// JSON message codec
class JsonMessageCodec<T> implements MessageCodec<T> {
  /// Constructor
  const JsonMessageCodec({
    required Map<String, dynamic>? Function(T) toJson,
    required T? Function(Map<String, dynamic>) fromJson,
  })  : _toJson = toJson,
        _fromJson = fromJson;

  /// Function to convert an object to JSON
  final Map<String, dynamic>? Function(T) _toJson;

  /// Function to create an object from JSON
  final T? Function(Map<String, dynamic>) _fromJson;

  @override
  List<int>? encode(T message) {
    final json = _toJson(message);
    final jsonStr = jsonEncode(json);
    return utf8.encode(jsonStr);
  }

  @override
  T? decode(List<int> data) {
    final jsonStr = utf8.decode(data);
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    return _fromJson(json);
  }
}
