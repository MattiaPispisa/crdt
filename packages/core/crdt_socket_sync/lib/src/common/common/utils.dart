import 'dart:async';
import 'dart:convert';
import 'dart:math';

/// Generates a URL-safe, unguessable session identifier.
///
/// 16 bytes (128 bits) from a cryptographically secure RNG, base64url-encoded
/// with the `==` padding stripped (22 chars). The id is generated server-side,
/// echoed to the client and used as a broadcast identity, so it must be
/// unpredictable — hence [Random.secure] rather than [Random.new].
String generateSessionId() {
  final random = Random.secure();
  final values = List<int>.generate(16, (i) => random.nextInt(256));
  return base64Url.encode(values).substring(0, 22);
}

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

/// Best-effort read of the `documentId` field of a frame that could not be
/// decoded.
///
/// Returns `null` when the frame is not JSON or names no document — an answer
/// can still be sent, it just cannot say which document it is about.
String? documentIdOf(List<int> data) {
  try {
    final json = jsonDecode(utf8.decode(data));
    if (json is Map<String, dynamic>) {
      final id = json['documentId'];
      return id is String ? id : null;
    }
  } catch (_) {
    // Not JSON: no documentId to report.
  }
  return null;
}
