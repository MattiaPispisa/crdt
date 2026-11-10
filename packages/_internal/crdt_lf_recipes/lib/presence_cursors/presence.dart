// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_socket_sync/replica.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:flutter/painting.dart';

/// A note on this device, joined on the relay, with the presence of its peers.
typedef SharedNote =
    ({
      CRDTReplica replica,
      ClientAwarenessPlugin presence,
      CRDTFugueTextHandler text,
    });

// #docregion join
/// Opens the note on this device and joins it on the relay at [url], as
/// [name] drawn in [color].
Future<SharedNote> openNote(
  String url, {
  required String name,
  required Color color,
}) async {
  // Sent on every connection: who this peer is, before any caret.
  final presence = ClientAwarenessPlugin(
    initialMetadata: {'name': name, 'color': color.toARGB32()},
  );
  final replica = await CRDTReplica.open(
    documentId: 'note',
    storage: CRDTHive.open,
    sync:
        (document) => WebSocketRelayClient(
          url: url,
          document: document,
          author: document.peerId,
          plugins: [presence],
        ),
  );
  // The cursors need a Fugue text: its anchors stay valid after any edit.
  final text = CRDTFugueTextHandler(replica.document, 'note');
  return (replica: replica, presence: presence, text: text);
}
// #enddocregion join

// #docregion publish
/// Publishes the caret of this peer; `null` [base] takes it away.
void publishCaret(
  ClientAwarenessPlugin presence,
  FugueElementID? base,
  FugueElementID? extent,
) {
  presence.updateLocalState({
    'cursor':
        base == null
            ? null
            : {
              'base': base.toJson(),
              if (extent != null) 'extent': extent.toJson(),
            },
  });
}
// #enddocregion publish

// #docregion read
/// The carets of the other peers in [awareness], ready to draw.
List<CrdtTextCursor> remoteCursors(
  ClientAwarenessPlugin presence,
  DocumentAwareness awareness,
) {
  return [
    for (final state in awareness.states.values)
      // The states include this peer: leave it out.
      if (state.clientId != presence.client.sessionId)
        if (state.metadata['cursor']
            case {'base': final Map<String, dynamic> base} && final cursor)
          CrdtTextCursor(
            id: state.clientId,
            label: state.metadata['name'] as String?,
            color: Color(state.metadata['color'] as int? ?? 0xFF2196F3),
            base: FugueElementID.fromJson(base),
            extent: switch (cursor['extent']) {
              final Map<String, dynamic> extent => FugueElementID.fromJson(
                extent,
              ),
              _ => null,
            },
          ),
  ];
}

// #enddocregion read
