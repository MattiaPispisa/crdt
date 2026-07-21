import 'dart:async';
import 'dart:ui';

import 'package:crdt_lf/crdt_lf.dart';
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

/// Ephemeral presence: keeps the map of remote peers and publishes the local
/// state (name, color, text cursor) through [outbound], throttled so caret
/// movement doesn't flood the socket.
class AwarenessService {
  AwarenessService({
    required this.name,
    required this.color,
    this.throttle = const Duration(milliseconds: 75),
  });

  final String name;
  final Color color;
  final Duration throttle;

  /// Hooked by the sync client to send the local state over the wire.
  void Function(Map<String, dynamic> state)? outbound;

  /// Remote peers keyed by clientId (the peerId used on the socket URL).
  final ValueNotifier<Map<String, PeerState>> peers = ValueNotifier(const {});

  FugueElementID? _base;
  FugueElementID? _extent;
  Timer? _throttleTimer;
  bool _dirty = false;

  Map<String, dynamic> get localState => PeerState(
    name: name,
    color: color,
    base: _base,
    extent: _extent,
  ).toJson();

  /// Updates the local text cursor; `null` anchors withdraw it (blur).
  /// Trailing-edge throttled.
  void setLocalCursor(FugueElementID? base, FugueElementID? extent) {
    _base = base;
    _extent = extent;
    if (_throttleTimer?.isActive ?? false) {
      _dirty = true;
      return;
    }
    _publish();
    _throttleTimer = Timer(throttle, () {
      if (_dirty) {
        _dirty = false;
        _publish();
      }
    });
  }

  /// Sends the current local state immediately (connect/reconnect).
  void republish() => _publish();

  void _publish() => outbound?.call(localState);

  /// Replaces the peer map with the states received in a `welcome`.
  void seedPeers(Map<String, Map<String, dynamic>> states) {
    peers.value = {
      for (final entry in states.entries)
        entry.key: PeerState.fromJson(entry.value),
    };
  }

  void updatePeer(String clientId, Map<String, dynamic> state) {
    peers.value = {...peers.value, clientId: PeerState.fromJson(state)};
  }

  void removePeer(String clientId) {
    final next = {...peers.value}..remove(clientId);
    peers.value = next;
  }

  void dispose() {
    _throttleTimer?.cancel();
    peers.dispose();
  }
}
