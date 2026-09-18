import 'package:crdt_socket_sync/src/common/client/status.dart';
import 'package:crdt_socket_sync/src/common/common/common.dart';

/// Why the server refused this client build.
///
/// A permanent condition: reconnecting cannot fix it, only a newer client (or
/// an older document) can. A client that holds one stops trying and stays in
/// [ConnectionStatus.unsupported].
class SyncIncompatibility {
  /// Records a refusal the server sent as [code], explained by [message].
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

  /// Whether [code] is a refusal a client cannot recover from.
  ///
  /// The recoverable codes travel on the same `ErrorMessage`; the terminal ones
  /// are listed in [Protocol.terminalErrors].
  static bool isTerminalCode(String code) =>
      Protocol.terminalErrors.contains(code);

  @override
  String toString() => 'SyncIncompatibility($code: $message)';
}
