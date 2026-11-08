// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:hive/hive.dart';

/// How many owners hold each Hive box this adapter opened.
///
/// Hive hands out one [Box] per name while it is open, so a close from one
/// owner would close it for every other owner too. An open here takes a
/// reference, a release gives one back, and the box closes with the last one.
///
/// A box opened or closed straight through Hive is outside this count.
abstract final class BoxReferences {
  static final Map<String, int> _counts = <String, int>{};

  static final Map<String, Future<void>> _closing = <String, Future<void>>{};

  /// Opens the box [name] and takes a reference to it.
  ///
  /// Waits first for a close of the same box that is still running, so it
  /// never hands out a box that is closing.
  static Future<Box<E>> open<E>(String name) async {
    final key = name.toLowerCase();
    for (var closing = _closing[key];
        closing != null;
        closing = _closing[key]) {
      await closing;
    }

    // Counted before the open suspends: a release in between keeps the box.
    _counts[key] = (_counts[key] ?? 0) + 1;
    try {
      return await Hive.openBox<E>(name);
    } catch (_) {
      _drop(key);
      rethrow;
    }
  }

  /// Gives back one reference to [box], and closes it with the last one.
  ///
  /// An open box nobody counted closes at once. A closed box is a no-op: it
  /// holds no reference, even when a newer box of that name is open.
  static Future<void> release(BoxBase<dynamic> box) {
    if (!box.isOpen) {
      return Future<void>.value();
    }
    if (_drop(box.name)) {
      return Future<void>.value();
    }
    return _close(box.name, box);
  }

  /// Closes the box [name] for every owner, so it can be deleted.
  static Future<void> closeNow<E>(String name) async {
    final key = name.toLowerCase();
    _counts.remove(key);
    if (Hive.isBoxOpen(key)) {
      await _close(key, Hive.box<E>(key));
    } else {
      await _closing[key];
    }
  }

  /// Closes every Hive box, and forgets every reference.
  static Future<void> closeAll() {
    _counts.clear();
    return Hive.close();
  }

  /// Gives back one reference to [key]; `true` when others are left.
  static bool _drop(String key) {
    final count = _counts.remove(key) ?? 0;
    if (count > 1) {
      _counts[key] = count - 1;
      return true;
    }
    return false;
  }

  static Future<void> _close(String key, BoxBase<dynamic> box) async {
    final closing = box.close();
    _closing[key] = closing;
    try {
      await closing;
    } finally {
      if (identical(_closing[key], closing)) {
        unawaited(_closing.remove(key));
      }
    }
  }
}
