import 'dart:async';

/// {@template outbound_buffer_overflow}
/// Thrown when an [OutboundQueue] would exceed its byte bound.
///
/// The connection that owns the queue should be torn down when this is raised:
/// a peer that cannot keep up with the outgoing stream is treated as gone. For
/// a CRDT the data is not lost — the peer re-syncs from its version vector on
/// the next handshake.
/// {@endtemplate}
class OutboundBufferOverflow implements Exception {
  /// {@macro outbound_buffer_overflow}
  ///
  /// Constructor
  const OutboundBufferOverflow({
    required this.attemptedBytes,
    required this.maxBufferSize,
  });

  /// The queue size (in bytes) that the rejected message would have produced.
  final int attemptedBytes;

  /// The configured maximum queued bytes.
  final int maxBufferSize;

  @override
  String toString() => 'OutboundBufferOverflow('
      'attempted: $attemptedBytes bytes, max: $maxBufferSize bytes)';
}

/// {@template outbound_queue}
/// A serialized, byte-bounded outbound send queue.
///
/// Messages are sent one at a time (each [add] waits for the previous send to
/// complete), which both preserves ordering and provides a natural
/// back-pressure point: when a consumer is slow, its `onSend` futures complete
/// slowly and the queued byte count grows. If the queued (not-yet-sent) bytes
/// would exceed `maxBufferSize`, [add] rejects with [OutboundBufferOverflow]
/// instead of buffering without bound.
/// {@endtemplate}
class OutboundQueue {
  /// {@macro outbound_queue}
  ///
  /// Constructor
  ///
  /// [onSend] performs the actual transport write for one message and must
  /// complete when the write is done (or fail on error).
  OutboundQueue({
    required Future<void> Function(List<int> data) onSend,
    required int maxBufferSize,
  })  : _onSend = onSend,
        _maxBufferSize = maxBufferSize;

  final Future<void> Function(List<int> data) _onSend;
  final int _maxBufferSize;

  /// Bytes enqueued but not yet sent.
  int _pendingBytes = 0;

  /// Tail of the send chain; each [add] links after it.
  Future<void> _tail = Future<void>.value();

  bool _closed = false;

  /// Bytes currently queued and waiting to be sent.
  int get pendingBytes => _pendingBytes;

  /// Whether the queue has been closed (manually or by an overflow).
  bool get isClosed => _closed;

  /// Enqueue [data] for sending.
  ///
  /// Returns a future that completes when this message has been sent (or fails
  /// if the send fails). Throws [OutboundBufferOverflow] synchronously — and
  /// closes the queue — if accepting the message would exceed `maxBufferSize`.
  Future<void> add(List<int> data) {
    if (_closed) {
      throw StateError('OutboundQueue is closed');
    }

    final projected = _pendingBytes + data.length;
    if (projected > _maxBufferSize) {
      _closed = true;
      throw OutboundBufferOverflow(
        attemptedBytes: projected,
        maxBufferSize: _maxBufferSize,
      );
    }

    _pendingBytes += data.length;

    final future = _tail.then((_) {
      // A later overflow may have closed the queue while this message waited;
      // drop it silently in that case (the connection is being torn down).
      if (_closed) {
        return null;
      }
      return _onSend(data);
    }).whenComplete(() {
      _pendingBytes -= data.length;
    });

    // Keep the chain alive even if this send fails.
    _tail = future.then((_) {}, onError: (_) {});

    return future;
  }

  /// Close the queue. Subsequent [add] calls throw and queued (not-yet-sent)
  /// messages are dropped.
  void close() {
    _closed = true;
  }
}
