// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_recipes/two_peers/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('both peers read the same merged text', () {
    // Every run draws new peer ids: the merge must not depend on them.
    for (var run = 0; run < 20; run++) {
      final (alice, bob) = mergeTwoPeers();
      expect(alice, 'Big Hello world!');
      expect(bob, 'Big Hello world!');
    }
  });
}
