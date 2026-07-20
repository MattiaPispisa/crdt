import 'dart:async';
import 'dart:ui';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:flutter/foundation.dart';

import 'package:greyhound_markdown_client/src/config.dart';

/// Presence state of a remote peer: identity plus an optional text cursor
/// anchored to stable fugue positions.
@immutable
class PeerState {
  const PeerState({
    required this.name,
    required this.color,
    this.base,
    this.extent,
  });

  factory PeerState.fromJson(Map<String, dynamic> json) {
    final cursor = json['cursor'] as Map<String, dynamic>?;
    return PeerState(
      name: json['name'] as String? ?? kDefaultUserName,
      color: Color(json['color'] as int? ?? 0xFF888888),
      base: cursor == null
          ? null
          : FugueElementID.fromJson(cursor['base'] as Map<String, dynamic>),
      extent: cursor?['extent'] == null
          ? null
          : FugueElementID.fromJson(cursor!['extent'] as Map<String, dynamic>),
    );
  }

  final String name;
  final Color color;
  final FugueElementID? base;
  final FugueElementID? extent;

  Map<String, dynamic> toJson() => {
    'name': name,
    'color': color.toARGB32(),
    'cursor': base == null
        ? null
        : {
            'base': base!.toJson(),
            if (extent != null) 'extent': extent!.toJson(),
          },
  };
}

/// Ephemeral presence, adapting the package's [ClientAwarenessPlugin] to the
/// UI: exposes remote peers as a [ValueNotifier] of [PeerState]s and
/// publishes the local state (name, color, text cursor) as plugin metadata.
///
/// Attach [plugin] to the room's `WebSocketRelayClient`; the client owns the
/// plugin lifecycle (it disposes it).
class AwarenessService {
  AwarenessService({
    required this.name,
    required this.color,
    Duration throttle = const Duration(milliseconds: 75),
  }) : plugin = ClientAwarenessPlugin(
         throttleDuration: throttle,
         initialMetadata: PeerState(name: name, color: color).toJson(),
       ) {
    _subscription = plugin.awarenessStream.listen(_onAwareness);
  }

  final String name;
  final Color color;

  /// The underlying awareness plugin, to be passed to the sync client.
  final ClientAwarenessPlugin plugin;

  /// Remote peers keyed by session id (self excluded).
  final ValueNotifier<Map<String, PeerState>> peers = ValueNotifier(const {});

  StreamSubscription<DocumentAwareness>? _subscription;

  void _onAwareness(DocumentAwareness awareness) {
    final sessionId = plugin.client.sessionId;
    peers.value = {
      for (final entry in awareness.states.entries)
        // Skip self and peers that have not published a state yet
        // (a fresh joiner has empty metadata until its first update).
        if (entry.key != sessionId && entry.value.metadata.isNotEmpty)
          entry.key: PeerState.fromJson(entry.value.metadata),
    };
  }

  /// Updates the local text cursor; `null` anchors withdraw it (blur).
  /// Throttled by the plugin.
  void setLocalCursor(FugueElementID? base, FugueElementID? extent) {
    // The plugin merges metadata, so name/color (from initialMetadata) are
    // preserved and `cursor: null` withdraws the cursor.
    plugin.updateLocalState({
      'cursor': base == null
          ? null
          : {
              'base': base.toJson(),
              if (extent != null) 'extent': extent.toJson(),
            },
    });
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    peers.dispose();
  }
}
