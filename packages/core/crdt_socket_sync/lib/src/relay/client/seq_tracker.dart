/// Tracks which prefix of the relay room log this client has imported.
///
/// The relay assigns one sequence number per change blob. The client learns
/// covered ranges from three sources: a welcome (the whole log up to its
/// `seq`), an ack of its own push, and rebroadcast changes of other clients.
/// Pushes of concurrent clients can reach this client out of order, so the
/// covered ranges may momentarily have holes.
///
/// [maxContiguous] is the highest sequence number `s` such that every entry
/// in `[1, s]` was imported. A snapshot upload must never cover more than
/// [maxContiguous]: the relay deletes the covered log entries, so a hole in
/// the snapshot would silently lose those changes for future joiners.
class RelaySeqTracker {
  int _maxContiguous = 0;

  /// Ranges above [_maxContiguous], as `[from exclusive, to inclusive]`
  final List<List<int>> _detached = [];

  /// The highest sequence number of the fully imported log prefix.
  int get maxContiguous => _maxContiguous;

  /// Marks the whole `[1, seq]` prefix as imported (welcome).
  void markThrough(int seq) {
    if (seq <= _maxContiguous) {
      return;
    }
    _maxContiguous = seq;
    _merge();
  }

  /// Marks the `(from, to]` range as imported (ack or rebroadcast).
  void addRange({required int from, required int to}) {
    if (to <= _maxContiguous) {
      return;
    }
    _detached.add([from, to]);
    _merge();
  }

  /// Absorbs into [_maxContiguous] every detached range it now touches.
  void _merge() {
    var merged = true;
    while (merged) {
      merged = false;
      for (var i = 0; i < _detached.length; i++) {
        final range = _detached[i];
        if (range[0] <= _maxContiguous) {
          if (range[1] > _maxContiguous) {
            _maxContiguous = range[1];
          }
          _detached.removeAt(i);
          merged = true;
          break;
        }
      }
    }
  }
}
