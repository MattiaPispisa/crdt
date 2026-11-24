// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:collection';

/// The first [length] elements of a list, read-only.
///
/// The list can grow after: the view keeps its [length].
class PrefixView<E> extends ListBase<E> {
  PrefixView(this._source, this.length)
    : assert(length <= _source.length, 'Longer than the list');

  final List<E> _source;

  @override
  final int length;

  @override
  set length(int _) => throw UnsupportedError('A read-only list');

  @override
  E operator [](int index) {
    RangeError.checkValidIndex(index, this, null, length);
    return _source[index];
  }

  @override
  void operator []=(int index, E value) =>
      throw UnsupportedError('A read-only list');
}

/// A list in reverse order, read-only.
class ReversedView<E> extends ListBase<E> {
  ReversedView(this._source);

  final List<E> _source;

  @override
  int get length => _source.length;

  @override
  set length(int _) => throw UnsupportedError('A read-only list');

  @override
  E operator [](int index) {
    RangeError.checkValidIndex(index, this, null, length);
    return _source[_source.length - 1 - index];
  }

  @override
  void operator []=(int index, E value) =>
      throw UnsupportedError('A read-only list');
}
