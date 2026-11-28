---
name: crdt-lf-app-setup
description: Use when you add crdt_lf to an app or change how a document lives in it - keeping it on the device, syncing it with other peers through a relay or a server, opening and closing it in a Flutter page, showing it in widgets, or sharing presence such as cursors.
---

# Set up crdt_lf in an app

A `CRDTDocument` lives in memory. Storage, sync and Flutter are packages
around it. This skill says which ones to add, how to wire them, and in what
order. Each rule links the page that explains why.

## Before you write code

- Read the versions in `pubspec.lock`. For signatures, read the dartdoc of the
  installed packages: their folders are in `.dart_tool/package_config.json`.
- Do not write the API from memory: it changes between major versions. Code
  written for an older version: follow the
  [migrations](https://mattiapispisa.it/crdt/docs/migrations).
- Start from the closest recipe below. Each one is a complete setup, run by a
  test.

## Decide

1. **Which packages.** Add only what the app needs:
   - keep it on the device: a storage adapter, such as `crdt_lf_hive` (also
     on the web), `crdt_lf_sqlite` (Dart VM and native Flutter), …
     [All the adapters](https://mattiapispisa.it/crdt/docs/connectors/persistence/adapters)
   - sync with other peers: `crdt_socket_sync`. A backend built on a server
     framework adds the adapter of that framework.
     [Server frameworks](https://mattiapispisa.it/crdt/docs/connectors/sync/server-frameworks)
   - Flutter widgets: `crdt_lf_flutter`. A rich text editor: `crdt_lf_quill`.
2. **Which sync mode.** A relay stores and forwards opaque changes: any
   backend, rooms on demand. A server–client server holds the documents and
   merges them. [Two modes](https://mattiapispisa.it/crdt/docs/connectors/sync#two-modes)
3. **Which recipe.** Open it and copy its shape:
   - [offline-first-replica](https://mattiapispisa.it/crdt/docs/recipes/offline-first-replica):
     Flutter, storage and relay sync in one call.
   - [flutter-note](https://mattiapispisa.it/crdt/docs/recipes/flutter-note):
     Flutter, storage only.
   - [notes-list](https://mattiapispisa.it/crdt/docs/recipes/notes-list):
     many documents in one app.
   - [shared-outline](https://mattiapispisa.it/crdt/docs/recipes/shared-outline):
     nested data, saved and synced.
   - [presence-cursors](https://mattiapispisa.it/crdt/docs/recipes/presence-cursors):
     who is in the room, and their carets.
   - [server-client-sync](https://mattiapispisa.it/crdt/docs/recipes/server-client-sync),
     [relay-rooms](https://mattiapispisa.it/crdt/docs/recipes/relay-rooms):
     a `dart:io` server and its clients.
   - None fits: [all the recipes](https://mattiapispisa.it/crdt/docs/recipes).

## Rules

1. Open the document with `CRDTReplica.open`: it restores the local copy,
   then connects. Without a replica, keep that order by hand.
   [Open a replica](https://mattiapispisa.it/crdt/docs/connectors/replica)
2. Keep one stable peer id per device. In an app, do not build the document
   with `CRDTDocument()`: the replica or `openDocument` restores the stored
   id. [Peer identity](https://mattiapispisa.it/crdt/docs/connectors/persistence/how-it-works#peer-identity)
3. `documentId` names the resource, the room: every peer of it opens the same
   id, and builds its handlers with the same ids.
   [The document](https://mattiapispisa.it/crdt/docs/document)
4. Build the handlers on `replica.document` after `open` returns. Register the
   kinds of nested handlers in `onDocument`, before the restore.
5. Close what you built on the document first (undo managers, listeners), then
   `await replica.close()`. Never dispose a document that a replica or a
   backend owns.
6. Pass `onStorageError` (replica) or `onError` (persistence): without them a
   failure is silent. [When a write fails](https://mattiapispisa.it/crdt/docs/connectors/persistence/how-it-works#when-a-write-fails)
7. Set up the storage adapter before `open`: each one has its own step.
   [Adapters](https://mattiapispisa.it/crdt/docs/connectors/persistence/adapters)
8. Flutter: `CrdtProvider.value` on the document the replica opened, then
   `CrdtHandlerBuilder` or `CrdtTextFieldBuilder`. Do not rebuild with a
   `StreamBuilder` on the document and `setState`.
   [Flutter](https://mattiapispisa.it/crdt/docs/connectors/flutter)
9. Connection status: start from `connectionStatusValue`, the stream replays
   nothing. `ConnectionStatus.unsupported` means the app must be updated.
   [Versions and compatibility](https://mattiapispisa.it/crdt/docs/connectors/sync/compatibility)
10. Presence (who is online, carets, pointers) goes through the awareness
    plugin (`ClientAwarenessPlugin`), never into the document.
    [Awareness](https://mattiapispisa.it/crdt/docs/connectors/sync/plugins#awareness-plugin)
11. Do not call `takeSnapshot` on a client that syncs: the server or the relay
    chooses when to prune, and a prune drops the undo stacks.
    [Snapshots](https://mattiapispisa.it/crdt/docs/document/snapshots-history)
12. A server–client server serves only the documents it holds: add each one
    (`addDocument`), or its clients are refused. A relay needs nothing.
    [Server–client mode](https://mattiapispisa.it/crdt/docs/connectors/sync/server-client)

## Example

Open a note from the device, synced through a relay:

<!-- recipe:offline-first-replica/open_note.dart#open -->
```dart
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
```
<!-- /recipe -->

Open it in a page, and close it with the page:

<!-- recipe:offline-first-replica/note_page.dart#lifecycle -->
```dart
late final Future<CRDTReplica> _replica = openNote(widget.url);

@override
void dispose() {
  // Stops the sync, writes what is still waiting, closes the storage.
  unawaited(_replica.then((replica) => replica.close()));
  super.dispose();
}
```
<!-- /recipe -->
