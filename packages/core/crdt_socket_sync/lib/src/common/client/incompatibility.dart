import 'package:crdt_socket_sync/src/common/client/status.dart';
import 'package:crdt_socket_sync/src/common/common/common.dart';

/// Why the server refused this client build.
///
/// A permanent condition: reconnecting cannot fix it, only a newer client (or
/// an older document) can. A client that holds one stops trying and stays in
/// [ConnectionStatus.unsupported].
class SyncIncompatibility {
  /// Constructor
  const SyncIncompatibility({
    required this.code,
    required this.message,
  });

  /// The error code the server sent.
  final String code;

  /// The server's explanation.
  final String message;

  /// Whether the peers disagree on [Protocol.protocolVersion].
  bool get isProtocolVersionMismatch =>
      code == Protocol.errorUnsupportedProtocolVersion;

  /// Whether this build cannot decode operations the document holds.
  bool get isMissingOperationKinds => code == Protocol.errorUnsupportedClient;

  /// Whether [code] is one of the two permanent refusals.
  ///
  /// Used to tell a refusal apart from the recoverable error codes that travel
  /// on the same `ErrorMessage`.
  static bool isTerminalCode(String code) =>
      code == Protocol.errorUnsupportedProtocolVersion ||
      code == Protocol.errorUnsupportedClient;

  @override
  String toString() => 'SyncIncompatibility($code: $message)';
}
