import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:crdt_socket_sync_client_example/awareness_text_presence.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:shared_examples_infrastructure/shared_examples_infrastructure.dart';

/// An [ExampleSyncSession] backed by a real [WebSocketClient].
///
/// Creates a [CRDTDocument] for the given `documentId` and `author`, hands it to
/// a client pointed at `url`, and connects. The client owns the local ⇄ remote
/// sync; this session just exposes the [document] (for the shared example UI)
/// and the [client] (for the connection indicator), and tears both down on
/// [dispose].
///
/// The socket example uses **one** session per screen: this app instance is a
/// single real peer. Run several instances to collaborate.
class SocketSyncSession implements ExampleSyncSession {
  /// Creates and connects a session to `url` for `documentId`.
  ///
  /// `metadata` seeds the awareness plugin (presence) sent to the server.
  SocketSyncSession({
    required String url,
    required String documentId,
    required PeerId author,
    required this.label,
    Map<String, dynamic>? metadata,
  }) : document = CRDTDocument(
         documentId: documentId,
         peerId: author,
         initialClock: HybridLogicalClock.now(),
       ) {
    awareness = ClientAwarenessPlugin(
      initialMetadata: metadata,
      throttleDuration: const Duration(milliseconds: 100),
    );
    client = WebSocketClient(
      url: url,
      document: document,
      author: author,
      // The demo servers run the awareness plugin, so the client must too —
      // otherwise it can't decode the awareness messages the server sends.
      plugins: [awareness],
    );
    textPresence = AwarenessTextCursorPresence(
      awareness: awareness,
      // Assigned by the server on connect: read it lazily.
      localSessionId: () => client.sessionId,
    );
    unawaited(client.connect());
  }

  @override
  final CRDTDocument document;

  @override
  final String label;

  /// The underlying client (exposed for the connection-status indicator).
  late final WebSocketClient client;

  /// The awareness (presence/cursors) plugin for this session.
  late final ClientAwarenessPlugin awareness;

  /// In-field text cursors over the awareness plugin (see
  /// [AwarenessTextCursorPresence]).
  @override
  late final AwarenessTextCursorPresence textPresence;

  @override
  void dispose() {
    textPresence.dispose();
    client.dispose();
    document.dispose();
  }
}
