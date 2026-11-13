// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// #docregion open
import 'package:crdt_lf_sqlite/crdt_lf_sqlite.dart';
import 'package:crdt_socket_sync/replica.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';

import 'outline.dart';

/// Opens the outline stored in the file [path], and syncs it through the
/// relay at [url].
///
/// Completes once the local copy is ready, even when the relay is down.
Future<CRDTReplica> openOutline(String url, {required String path}) {
  return CRDTReplica.open(
    // The relay room: every peer of the outline opens the same id.
    documentId: 'outline',
    // One file per device: it also keeps the peer id of this device.
    storage: () => CRDTSqlite.open(path),
    sync:
        (document) => WebSocketRelayClient(
          url: url,
          document: document,
          author: document.peerId,
        ),
    // Before the restore: the kinds the stored tree is rebuilt from.
    onDocument: registerKinds,
  );
}
// #enddocregion open
