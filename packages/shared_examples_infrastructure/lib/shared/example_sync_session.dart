import 'package:crdt_lf/crdt_lf.dart';

/// A transport-agnostic handle to one synced [CRDTDocument] shown in a pane.
///
/// Implementations own the transport (a simulated in-memory network, or a real
/// WebSocket client) and the document lifecycle: they wire local ⇄ remote sync
/// and, on [dispose], tear everything down. The shared example UI only reads
/// [document] and shows [label]; it never talks to a transport directly.
///
/// - The crdt_lf example provides a session over a simulated `Network`
///   (multiple peers over one in-memory bus), and passes **two** of them per
///   example screen (side-by-side peers).
/// - The crdt_socket_sync example provides a session backed by a real
///   `WebSocketClient`, and passes **one** per screen (this app instance is a
///   single real peer; run several instances to collaborate).
abstract class ExampleSyncSession {
  /// The already-synced document backing the pane.
  CRDTDocument get document;

  /// The pane label (tab title in the narrow layout), e.g. `'Peer 1'`.
  String get label;

  /// Tears down the transport and the document.
  void dispose();
}
