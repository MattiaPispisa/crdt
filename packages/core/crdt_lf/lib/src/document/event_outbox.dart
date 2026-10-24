// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

/// Holds the events a document publishes until it is settled, then hands
/// them out in the order they were published.
///
/// Holding them moves delivery from the middle of the work to its end, so no
/// listener runs on a half-applied document.
class EventOutbox {
  List<void Function()>? _pending;

  bool _flushing = false;

  /// Holds [deliver] until the next [flush].
  ///
  /// The first event after a flush also schedules a flush on a microtask, so
  /// an event published outside any transaction still goes out.
  void add(void Function() deliver) {
    final pending = _pending;
    if (pending != null) {
      pending.add(deliver);
      return;
    }
    _pending = <void Function()>[deliver];
    scheduleMicrotask(flush);
  }

  /// Hands out every event waiting here.
  ///
  /// A listener may write back, publishing more events; they go out in this
  /// same pass, after it returns. A listener that throws is reported to the
  /// current zone, and the events behind it still go out. A nested call does
  /// nothing: the pass it would repeat is already running.
  void flush() {
    if (_flushing) {
      return;
    }
    _flushing = true;
    try {
      while (true) {
        final pending = _pending;
        if (pending == null) {
          return;
        }
        _pending = null;
        for (final deliver in pending) {
          try {
            deliver();
          } catch (error, stack) {
            // A handler delta goes out on a synchronous controller, so a
            // subscriber that throws throws right here. Letting it out would
            // drop every event queued behind it — a document event a
            // persistence adapter is waiting for included: the list is already
            // detached and nothing requeues it.
            Zone.current.handleUncaughtError(error, stack);
          }
        }
      }
    } finally {
      _flushing = false;
    }
  }
}
