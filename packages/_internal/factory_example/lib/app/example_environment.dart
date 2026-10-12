import 'dart:async';

import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_socket_sync/replica.dart';
import 'package:factory_example/app/example_sync.dart';
import 'package:factory_example/shared/app_bar_links.dart';
import 'package:flutter/foundation.dart';

/// What the screens of an `ExampleApp` share: the sync, the
/// links, and one storage backend per peer.
///
/// Provided above the routes, so a screen reads it with `context.read`.
class ExampleEnvironment {
  /// Creates the environment; `null` [storage] keeps documents in memory.
  ExampleEnvironment({
    required this.sync,
    required this.links,
    required ExampleStorage? storage,
  }) : _storage = storage,
       _backends = {},
       _closing = {};

  /// The sync of every replica.
  final ExampleSync sync;

  /// The external links shown in every app bar.
  final AppBarLinks links;

  final ExampleStorage? _storage;

  final Map<String, Future<CRDTStorageBackend>> _backends;

  final Map<String, Future<void>> _closing;

  /// Opens [documentId] for [peer] and starts to sync it.
  ///
  /// Waits for a [close] of the same document and peer to end first. A
  /// storage that fails leaves the document in memory.
  Future<CRDTReplica> open(String documentId, ExamplePeer peer) async {
    // The screen left a moment ago may still be writing this document down.
    await _closing[_key(documentId, peer)];

    final storage = _storage;
    return CRDTReplica.open(
      documentId: documentId,
      storage:
          storage == null
              ? null
              : () => _backends.putIfAbsent(
                peer.key,
                () => Future.sync(() => storage(peer)),
              ),
      ownsStorage: false,
      sync: (document) => sync.createClient(document, peer),
      onStorageError: (error, stackTrace) {
        debugPrint('Storage of ${peer.label} failed: $error\n$stackTrace');
      },
    );
  }

  /// Closes [replica], opened by [open] for [documentId] and [peer].
  ///
  /// Returns at once; a failure is logged.
  void close(String documentId, ExamplePeer peer, CRDTReplica replica) {
    final key = _key(documentId, peer);
    final closing = replica.close().catchError((Object error, StackTrace st) {
      debugPrint('Closing ${peer.label} failed: $error\n$st');
    });
    _closing[key] = closing;
    unawaited(
      closing.whenComplete(
        () => _closing.removeWhere((_, value) => identical(value, closing)),
      ),
    );
  }

  /// Waits for the replicas being closed, then closes the backends.
  Future<void> dispose() async {
    await Future.wait(_closing.values);
    for (final backend in _backends.values) {
      try {
        await (await backend).close();
      } catch (_) {
        // A backend that failed to open has nothing to close.
      }
    }
    _backends.clear();
  }

  static String _key(String documentId, ExamplePeer peer) =>
      '${peer.key}/$documentId';
}
