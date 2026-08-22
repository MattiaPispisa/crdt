import 'dart:math';

/// Constants of the relay protocol.
///
/// Values shared by both the relay protocol peers complement the core
/// `Protocol` constants (handshake timeout, ping cadence, buffer bound),
/// which apply to the relay implementations unchanged.
class RelayProtocol {
  /// Base delay of the client exponential reconnect backoff.
  static const Duration reconnectBaseDelay = Duration(milliseconds: 500);

  /// Maximum delay of the client exponential reconnect backoff.
  static const Duration reconnectMaxDelay = Duration(milliseconds: 10000);

  /// Maximum random jitter added to every reconnect delay.
  static const Duration reconnectJitter = Duration(milliseconds: 250);

  /// Room log length beyond which the relay asks a client to upload a
  /// snapshot to compact the log.
  static const int logCompactThreshold = 200;

  /// Minimum time between two compaction requests for the same room.
  ///
  /// Rate-limits the `compact` flag so only one client at a time is asked
  /// to upload a snapshot.
  static const Duration compactRetryInterval = Duration(seconds: 30);

  /// The delay before reconnect attempt number [attempts] (0-based).
  ///
  /// Exponential backoff with jitter:
  /// `min(baseDelay * 2^attempts, maxDelay) + random(jitter)`.
  static Duration reconnectDelay(
    int attempts, {
    Duration baseDelay = reconnectBaseDelay,
    Duration maxDelay = reconnectMaxDelay,
    Duration jitter = reconnectJitter,
    Random? random,
  }) {
    // Cap the shift so the doubling cannot overflow.
    final shift = min(attempts, 20);
    final delay = min(
      baseDelay.inMilliseconds << shift,
      maxDelay.inMilliseconds,
    );
    final jitterMs = jitter.inMilliseconds <= 0
        ? 0
        : (random ?? Random()).nextInt(jitter.inMilliseconds + 1);
    return Duration(milliseconds: delay + jitterMs);
  }
}
