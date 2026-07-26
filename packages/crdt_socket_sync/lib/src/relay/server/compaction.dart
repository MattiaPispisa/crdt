import 'package:crdt_socket_sync/src/relay/common/protocol.dart';

/// {@template relay_compaction_coordinator}
/// Decides when the relay asks a client to upload a snapshot to compact a
/// room log.
///
/// One coordinator is shared by every session of a relay server so that at
/// most one client per room is asked at a time: once [shouldCompact] returns
/// `true` for a room, it returns `false` for the retry interval, giving the
/// asked client time to upload before another client is bothered.
/// {@endtemplate}
class RelayCompactionCoordinator {
  /// {@macro relay_compaction_coordinator}
  ///
  /// Constructor
  RelayCompactionCoordinator({
    int? logCompactThreshold,
    Duration? retryInterval,
    DateTime Function()? now,
  })  : _logCompactThreshold =
            logCompactThreshold ?? RelayProtocol.logCompactThreshold,
        _retryInterval = retryInterval ?? RelayProtocol.compactRetryInterval,
        _now = now ?? DateTime.now;

  /// Room log length beyond which compaction is requested
  final int _logCompactThreshold;

  /// Minimum time between two compaction requests for the same room
  final Duration _retryInterval;

  /// Clock, injectable for tests
  final DateTime Function() _now;

  /// When each room was last asked to compact
  final Map<String, DateTime> _compactAskedAt = {};

  /// Whether the client currently being answered should be asked to upload
  /// a snapshot for [roomId], given the current [logLength].
  ///
  /// Returning `true` stamps the rate limit for [roomId].
  bool shouldCompact(String roomId, int logLength) {
    if (logLength <= _logCompactThreshold) {
      return false;
    }

    final askedAt = _compactAskedAt[roomId];
    if (askedAt != null && _now().difference(askedAt) < _retryInterval) {
      return false;
    }

    _compactAskedAt[roomId] = _now();
    return true;
  }

  /// Clears the rate limit for [roomId].
  ///
  /// Called when a snapshot upload lands, so the next threshold crossing can
  /// ask again immediately.
  void reset(String roomId) {
    _compactAskedAt.remove(roomId);
  }
}
