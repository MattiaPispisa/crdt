// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:flutter/material.dart';

import 'presence.dart';

/// A page that edits [note] and shows the carets of the other peers.
class NotePage extends StatelessWidget {
  /// Creates the page of [note].
  const NotePage({required this.note, super.key});

  /// The note, its client and its presence.
  final SharedNote note;

  // #docregion bind
  @override
  Widget build(BuildContext context) {
    final presence = note.presence;
    return Scaffold(
      appBar: AppBar(title: const Text('Note')),
      body: CrdtProvider.value(
        value: note.client.document,
        child: CrdtTextFieldBuilder(
          id: 'note',
          // Reported while the field has focus, `null`s when it loses it.
          onSelectionAnchorsChanged:
              (base, extent) => publishCaret(presence, base, extent),
          // The builder does not run again when a remote caret moves: the
          // StreamBuilder redraws the cursors.
          builder:
              (context, controller) => StreamBuilder<DocumentAwareness>(
                stream: presence.awarenessStream,
                initialData: presence.awareness,
                builder:
                    (context, snapshot) => CrdtTextCursorsOverlay(
                      id: 'note',
                      cursors: remoteCursors(presence, snapshot.requireData),
                      child: TextField(
                        controller: controller,
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: 'Write here',
                          contentPadding: EdgeInsets.all(16),
                        ),
                      ),
                    ),
              ),
        ),
      ),
    );
  }

  // #enddocregion bind
}
