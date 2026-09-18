/// Something the client could not do with what the server sent.
///
/// It is not a refusal of the build (`SyncIncompatibility`) and not a
/// connection problem: the link works and the peers understand each other, but
/// this one piece of data could not be taken in. The connection stays up, and
/// the client keeps going with what it already had.
///
/// {@template sync_fault_not_thrown}
/// Reported on `CRDTSocketClient.faults`, never thrown: this runs inside the
/// callback that reads the socket, where a throw reaches no `catch` and no
/// `onError` and ends up as an uncaught error in the zone.
/// {@endtemplate}
///
/// Nothing is retried.
class SyncFault {
  /// Records that [reason] failed with [error].
  const SyncFault({
    required this.reason,
    required this.error,
    this.stackTrace,
  });

  /// What the client was doing, in a few words, ready to log.
  final String reason;

  /// What was thrown.
  final Object error;

  /// Where it was thrown, when the source had one to give.
  final StackTrace? stackTrace;

  @override
  String toString() => 'SyncFault($reason: $error)';
}
