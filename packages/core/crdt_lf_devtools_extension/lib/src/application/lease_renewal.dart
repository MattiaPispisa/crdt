// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

/// Renews, on a timer, a lease the app holds for the extension.
class LeaseRenewal {
  /// Calls [onMissed] when a renewal finds the work stopped in the app.
  LeaseRenewal({required this.every, required void Function() onMissed})
    : _onMissed = onMissed;

  /// The time between two renewals.
  final Duration every;

  final void Function() _onMissed;

  Timer? _timer;

  /// Calls [renew] every [every] until [stop].
  ///
  /// [renew] answers `false` when the app had stopped the work.
  void start(Future<bool> Function() renew) {
    stop();
    _timer = Timer.periodic(every, (_) => unawaited(_renew(renew)));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _renew(Future<bool> Function() renew) async {
    try {
      if (!await renew()) _onMissed();
    } on Object {
      // The next tick tries again.
    }
  }
}
