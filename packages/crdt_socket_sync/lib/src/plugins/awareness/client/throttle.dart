import 'dart:async';

/// Throttler
///
/// Leading + trailing edge: the first call in a window fires immediately;
/// further calls within the window are coalesced and the latest one fires when
/// the window elapses. This guarantees the final action in a burst (e.g. the
/// last cursor position) is not dropped.
class Throttler {
  /// Constructor
  Throttler(this.duration);

  /// throttle duration
  final Duration duration;
  Timer? _timer;

  /// The most recent action received while the window was open, if any.
  void Function()? _pending;

  /// throttle the [action]
  void call(void Function() action) {
    if (_timer?.isActive ?? false) {
      // Window open: remember the latest action to run on the trailing edge.
      _pending = action;
      return;
    }
    // Leading edge: fire immediately and open the window.
    action();
    _startWindow();
  }

  void _startWindow() {
    _timer = Timer(duration, () {
      final pending = _pending;
      _pending = null;
      if (pending != null) {
        // Trailing edge: run the latest coalesced action and keep throttling
        // in case more calls arrived meanwhile.
        pending();
        _startWindow();
      }
    });
  }

  /// dispose the Throttler
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }
}
