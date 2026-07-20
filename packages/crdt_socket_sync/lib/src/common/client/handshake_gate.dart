import 'dart:async';

/// Coordinates the client-side handshake lifecycle.
///
/// Owns the [Completer] for a single handshake attempt: [perform] opens an
/// attempt and races the peer's reply against a timeout, [succeed] resolves it
/// once the reply arrives, and [reset] fails and clears it. The status getters
/// ([inProgress], [isActive], [pending], [completed]) expose that state so an
/// outbound frame can be gated until the handshake completes.
class HandshakeGate {
  /// Completer for the in-flight handshake.
  ///
  /// `null` when no handshake has started; non-null (and possibly completed)
  /// once one has, until [reset] clears it.
  Completer<bool>? _completer;

  /// Whether a handshake is in flight (started and not yet resolved).
  bool get inProgress => _completer != null && !_completer!.isCompleted;

  /// Whether a handshake attempt exists (in flight or already resolved).
  ///
  /// Stays `true` after the handshake resolves, until [reset] clears it — this
  /// is what a transport error checks before tearing an attempt down.
  bool get isActive => _completer != null;

  /// The in-flight handshake future, or `null` when none is [inProgress].
  ///
  /// Used to join an attempt that is already running instead of starting a
  /// new one.
  Future<bool>? get pending => inProgress ? _completer!.future : null;

  /// Resolves to `true` only once the handshake has completed successfully.
  ///
  /// Returns `false` immediately (no waiting) while no handshake exists or one
  /// is still in flight — callers use it to gate outbound frames.
  Future<bool> get completed {
    final completer = _completer;
    if (completer == null || !completer.isCompleted) {
      return Future.value(false);
    }
    return completer.future;
  }

  /// Starts a fresh handshake and races [send] against [timeout].
  ///
  /// [send] transmits the opening frame; the peer's reply completes the
  /// handshake from elsewhere (via [succeed]). Returns `true` if the reply
  /// wins the race, `false` on timeout or if [send] throws.
  Future<bool> perform({
    required Future<void> Function() send,
    required Duration timeout,
  }) async {
    _completer = Completer<bool>();

    try {
      // Do not attempt to reconnect on a send failure here: the reconnect
      // machinery handles it. On failure the send path may already have
      // reset (and nulled) the completer, so completing below is null-guarded.
      await send();

      final timeoutFuture = Future.delayed(timeout, () => false);

      // Race the reply against the timeout. [succeed] resolves the completer
      // when the peer's reply arrives in the message-handling code.
      return await Future.any([_completer!.future, timeoutFuture]);
    } catch (_) {
      _completer?.complete(false);
      return false;
    }
  }

  /// Marks the in-flight handshake as successful (peer reply received).
  ///
  /// A no-op when no handshake is in flight, so a duplicate or late reply
  /// cannot throw on an already-resolved completer.
  void succeed() {
    final completer = _completer;
    if (completer != null && !completer.isCompleted) {
      completer.complete(true);
    }
  }

  /// Resolves any in-flight handshake as failed and clears it.
  ///
  /// After this the gate is back to its initial state ([isActive] is `false`).
  void reset() {
    if (_completer?.isCompleted == false) {
      _completer?.complete(false);
    }
    _completer = null;
  }
}
