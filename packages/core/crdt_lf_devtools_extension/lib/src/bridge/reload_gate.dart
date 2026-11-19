// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

/// Runs a load at most once per [delay], and loses no request.
class ReloadGate {
  ReloadGate(this._load, {this.delay = const Duration(milliseconds: 100)});

  final Future<void> Function() _load;

  /// How long a first request waits, so that a burst shares one load.
  final Duration delay;

  Timer? _timer;

  Completer<void>? _pending;

  bool _running = false;

  bool _disposed = false;

  /// Asks for a load.
  ///
  /// Completes when a load that started after this call ends, and fails
  /// with its error. A request made during a load gets one more load.
  Future<void> request() {
    if (_disposed) return Future.value();
    final pending = _pending ??= Completer<void>();
    if (!_running) _timer ??= Timer(delay, _run);
    return pending.future;
  }

  Future<void> _run() async {
    _timer = null;
    final served = _pending;
    _pending = null;
    if (served == null || _disposed) return;
    _running = true;
    try {
      await _load();
      served.complete();
    } on Object catch (e, s) {
      served.completeError(e, s);
    } finally {
      _running = false;
    }
    if (_pending != null && !_disposed) _timer ??= Timer(delay, _run);
  }

  /// Cancels the waiting load and completes the pending requests.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending?.complete();
    _pending = null;
  }
}
