// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:crdt_socket_sync/replica.dart';
import 'package:flutter/material.dart';

import 'open_note.dart';

/// A page that edits the note, stored on this device and synced through the
/// relay at [url].
class NotePage extends StatefulWidget {
  /// Creates the page of the note synced through the relay at [url].
  const NotePage({required this.url, super.key});

  /// The address of the relay server.
  final String url;

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
  // #docregion lifecycle
  late final Future<CRDTReplica> _replica = openNote(widget.url);

  @override
  void dispose() {
    // Stops the sync, writes what is still waiting, closes the storage.
    unawaited(_replica.then((replica) => replica.close()));
    super.dispose();
  }
  // #enddocregion lifecycle

  // #docregion bind
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CRDTReplica>(
      future: _replica,
      builder: (context, snapshot) {
        final replica = snapshot.data;
        if (replica == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Note'),
            actions: [ConnectionChip(client: replica.client!)],
          ),
          body: CrdtProvider.value(
            value: replica.document,
            child: CrdtTextFieldBuilder(
              id: 'note',
              builder:
                  (context, controller) => TextField(
                    controller: controller,
                    maxLines: null,
                    decoration: const InputDecoration(
                      hintText: 'Write here, online or not',
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
            ),
          ),
        );
      },
    );
  }
  // #enddocregion bind
}

// #docregion status
/// Shows the connection status of [client].
class ConnectionChip extends StatelessWidget {
  /// Creates a chip that follows the connection of [client].
  const ConnectionChip({required this.client, super.key});

  /// The client to follow.
  final CRDTSocketClient client;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectionStatus>(
      stream: client.connectionStatus,
      // The stream replays nothing: start from the current status.
      initialData: client.connectionStatusValue,
      builder: (context, snapshot) {
        final (label, icon) = switch (snapshot.requireData) {
          ConnectionStatus.connected => ('Online', Icons.cloud_done),
          ConnectionStatus.connecting => ('Connecting', Icons.cloud_upload),
          ConnectionStatus.reconnecting => ('Reconnecting', Icons.cloud_sync),
          ConnectionStatus.disconnected => ('Offline', Icons.cloud_off),
          ConnectionStatus.error => ('Offline', Icons.cloud_off),
          ConnectionStatus.unsupported => ('Update the app', Icons.error),
        };
        return Chip(avatar: Icon(icon, size: 18), label: Text(label));
      },
    );
  }
}
// #enddocregion status
