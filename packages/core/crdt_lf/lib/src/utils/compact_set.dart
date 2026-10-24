// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:collection';

/// A [Set] that holds its first element in a field and switches to a hash set
/// at the second.
///
/// A hash set with one element costs ~200 bytes; this costs 32.
/// If a set is expected to hold more than one element, use [Set] instead.
class CompactSet<E> extends SetBase<E> {
  /// Creates an empty set.
  CompactSet();

  E? _one;
  bool _hasOne = false;
  Set<E>? _many;

  @override
  int get length => _many?.length ?? (_hasOne ? 1 : 0);

  @override
  bool get isEmpty => length == 0;

  @override
  bool get isNotEmpty => length != 0;

  @override
  Iterator<E> get iterator {
    final many = _many;
    if (many != null) {
      return many.iterator;
    }
    return _hasOne ? _SingleIterator<E>(_one as E) : <E>[].iterator;
  }

  @override
  bool contains(Object? element) {
    final many = _many;
    if (many != null) {
      return many.contains(element);
    }
    return _hasOne && _one == element;
  }

  @override
  E? lookup(Object? element) {
    final many = _many;
    if (many != null) {
      return many.lookup(element);
    }
    return _hasOne && _one == element ? _one : null;
  }

  @override
  bool add(E value) {
    final many = _many;
    if (many != null) {
      return many.add(value);
    }
    if (!_hasOne) {
      _one = value;
      _hasOne = true;
      return true;
    }
    if (_one == value) {
      return false;
    }
    _many = <E>{_one as E, value};
    _one = null;
    _hasOne = false;
    return true;
  }

  @override
  bool remove(Object? value) {
    final many = _many;
    if (many == null) {
      if (!_hasOne || _one != value) {
        return false;
      }
      _one = null;
      _hasOne = false;
      return true;
    }
    if (!many.remove(value)) {
      return false;
    }
    if (many.length == 1) {
      _one = many.first;
      _hasOne = true;
      _many = null;
    }
    return true;
  }

  @override
  void clear() {
    _one = null;
    _hasOne = false;
    _many = null;
  }

  @override
  Set<E> toSet() => Set<E>.of(this);
}

class _SingleIterator<E> implements Iterator<E> {
  _SingleIterator(this.current);

  @override
  final E current;

  bool _moved = false;

  @override
  bool moveNext() {
    final first = !_moved;
    _moved = true;
    return first;
  }
}
