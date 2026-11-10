// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:flutter/material.dart';

import 'presence.dart';

/// A page that edits the note shared through the relay at [url], and shows
/// the carets of the other peers.
class NotePage extends StatefulWidget {
  /// Creates the page of the note, for the peer [name] drawn in [color].
  const NotePage({
    required this.url,
    required this.name,
    required this.color,
    super.key,
  });

  /// The address of the relay server.
  final String url;

  /// The name the other peers see next to the caret of this peer.
  final String name;

  /// The color of the caret of this peer.
  final Color color;

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  // #docregion lifecycle
  late final Future<SharedNote> _note = openNote(
    widget.url,
    name: widget.name,
    color: widget.color,
  );

  @override
  void dispose() {
    // Stops the sync, writes what is still waiting, closes the storage.
    unawaited(_note.then((note) => note.replica.close()));
    super.dispose();
  }
  // #enddocregion lifecycle

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SharedNote>(
      future: _note,
      builder:
          (context, snapshot) => switch (snapshot.data) {
            final note? => _buildNote(note),
            null => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          },
    );
  }

  // #docregion bind
  Widget _buildNote(SharedNote note) {
    final presence = note.presence;
    return Scaffold(
      appBar: AppBar(title: const Text('Note')),
      body: CrdtProvider.value(
        value: note.replica.document,
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
