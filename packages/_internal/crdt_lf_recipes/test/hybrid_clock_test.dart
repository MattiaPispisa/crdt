// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_recipes/hybrid_clock/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a received message comes before the clock, and both forms '
      'read back the same clock', () {
    final [ordered, fromInt, fromBytes] = runClock();
    expect(ordered, isTrue);
    expect(fromInt, isTrue);
    expect(fromBytes, isTrue);
  });
}
