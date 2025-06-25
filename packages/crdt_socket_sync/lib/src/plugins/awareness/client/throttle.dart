import 'dart:async';

/// Throttler
class Throttler {
  /// Constructor
  Throttler(this.duration);

  /// throttle duration
  final Duration duration;
  Timer? _timer;

  /// throttle the [action]
  void call(void Function() action) {
    if (_timer?.isActive ?? false) {
      return;
    }
    _timer = Timer(duration, () {});
    action();
  }

  /// dispose the Throttler
  void dispose() {
    _timer?.cancel();
  }
}
