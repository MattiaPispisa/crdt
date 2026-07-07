import 'dart:async';
import 'dart:convert';

/// Try to execute a function and ignore the error
Future<void> tryCatchIgnore(FutureOr<void> Function() fn) async {
  try {
    await fn();
  } catch (e) {
    // Ignore the error
  }
}

/// Normalize a raw WebSocket frame into transport bytes.
///
/// A frame is either a `String` (text frame) or a `List<int>` (binary frame).
/// Text frames are decoded with [utf8] to stay symmetric with how both the
/// client and the server encode outgoing text (`utf8.encode`).
List<int> frameToBytes(Object? data) {
  if (data is String) {
    return utf8.encode(data);
  }
  if (data is List<int>) {
    return data;
  }
  throw FormatException('Unexpected data type: ${data.runtimeType}');
}
