// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

/// The changes loaded so far, and the document total.
typedef LoadProgress = ({int loaded, int total});

/// The outcome of the last load of a cubit.
enum LoadStatus {
  /// No load ended yet.
  initial,

  /// The last load succeeded.
  loaded,

  /// The last load failed.
  failure,
}
