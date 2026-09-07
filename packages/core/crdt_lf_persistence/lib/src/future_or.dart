import 'dart:async';

/// Chaining for a value that may or may not be a [Future].
extension CRDTFutureOr<T> on FutureOr<T> {
  /// Runs [then] on this value, and returns what it gives back.
  ///
  /// A synchronous value is passed straight to [then], so nothing suspends.
  /// A [Future] is chained with [Future.then] instead.
  ///
  /// This is what keeps a synchronous backend synchronous. `await` suspends
  /// even when what it waits on is not a future, so a chain of awaits would
  /// put the microtask queue between every two steps of a write that a
  /// backend like sqlite performs without ever suspending.
  FutureOr<R> chain<R>(FutureOr<R> Function(T value) then) {
    final value = this;
    return value is Future<T> ? value.then(then) : then(value);
  }
}
