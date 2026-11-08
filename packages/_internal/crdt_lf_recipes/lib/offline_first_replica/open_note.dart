// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// #docregion open
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_socket_sync/replica.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:flutter/foundation.dart';

/// Opens the note on this device, and syncs it through the relay at [url].
///
/// Completes once the local copy is ready, even when the relay is down.
Future<CRDTReplica> openNote(String url) async {
  final replica = await CRDTReplica.open(
    // The relay room: every peer of the note opens the same id.
    documentId: 'note',
    storage: CRDTHive.open,
    sync:
        (document) => WebSocketRelayClient(
          url: url,
          document: document,
          author: document.peerId,
        ),
    // Without it, a storage that cannot be read makes `open` throw. With it,
    // the note starts empty and in memory.
    onStorageError: (error, stack) => debugPrint('Storage error: $error'),
  );
  CRDTFugueTextHandler(replica.document, 'note');
  return replica;
}
// #enddocregion open
