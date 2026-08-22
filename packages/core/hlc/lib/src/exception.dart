/// Exception thrown when a clock drift is detected.
///
/// This exception is thrown when the clock of a node is detected to be
/// drifting from the expected value.
///
/// This can happen when the node is not properly synchronized with the
/// other nodes in the system.
class ClockDriftException implements Exception {
  /// Creates a new [ClockDriftException] with the given message.
  const ClockDriftException(this.message);

  /// The message of the exception.
  final String message;

  @override
  String toString() => 'ClockDriftException: $message';
}
