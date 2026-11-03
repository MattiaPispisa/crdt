// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:editor_conformance/src/text_boundaries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const text = 'a😀b';

  test('runeBoundary never points into a surrogate pair', () {
    expect([
      for (var i = 0; i <= 5; i++) runeBoundary(text, i),
    ], [
      0,
      1,
      1,
      3,
      4,
      4,
    ]);
  });

  test('nextRune steps over a whole rune', () {
    expect(nextRune(text, 0), 1);
    expect(nextRune(text, 1), 3);
    expect(nextRune(text, 3), 4);
  });
}
