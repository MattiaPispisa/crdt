import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:factory_example/shared/awareness_text_presence.dart';
import 'package:factory_example/shared/text_cursor_presence.dart';
import 'package:flutter/widgets.dart';

/// One peer of the examples: a pane on every screen, with its own storage.
class ExamplePeer {
  /// Creates a peer.
  const ExamplePeer({required this.key, required this.label});

  /// Stable id of the peer, unique in its [ExampleSync]. Name storages after
  /// it, so each peer keeps its own copy.
  final String key;

  /// The pane label (tab title in the narrow layout), e.g. `'Peer 1'`.
  final String label;
}

/// Opens the backend that keeps the documents of [peer].
///
/// Called at most once per peer for the app lifetime. The app closes the
/// backend when it is disposed.
typedef ExampleStorage =
    FutureOr<CRDTStorageBackend> Function(ExamplePeer peer);

/// How the documents of the example app reach the other peers.
///
/// Every screen opens one `CRDTReplica` per peer of [peers], synced by the
/// client [createClient] builds.
abstract class ExampleSync {
  /// The peers every screen shows side by side.
  List<ExamplePeer> get peers;

  /// Builds the client that syncs [document] for [peer].
  ///
  /// The replica connects it once the document is restored, and disposes it
  /// when the screen closes.
  CRDTSocketClient createClient(CRDTDocument document, ExamplePeer peer);

  /// The in-field text cursors channel of [peer], owned and disposed by the
  /// screen; `null` for no text cursors.
  ///
  /// Defaults to the awareness plugin of [client], when it has one.
  TextCursorPresence? textPresence(CRDTSocketClient client, ExamplePeer peer) {
    final awareness = client.awareness;
    if (awareness == null) {
      return null;
    }
    return AwarenessTextCursorPresence(awareness);
  }

  /// The app-bar control that tunes this sync, shown on every page.
  Widget buildSettings(BuildContext context);
}

/// Reads the awareness plugin of a [CRDTSocketClient].
extension ExampleClientAwareness on CRDTSocketClient {
  /// The awareness plugin of this client; `null` when it has none.
  ClientAwarenessPlugin? get awareness =>
      plugins.whereType<ClientAwarenessPlugin>().firstOrNull;
}
