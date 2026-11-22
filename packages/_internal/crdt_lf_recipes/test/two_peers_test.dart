// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_recipes/two_peers/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('both peers read the same text, each insert whole', () {
    // Every run draws new peer ids: they pick the order, never the content.
    final seen = <String>{};
    for (var run = 0; run < 20; run++) {
      final (alice, bob) = mergeTwoPeers();
      expect(alice, bob);
      expect(alice, isIn(['Hello World Dart', 'Hello Dart World']));
      seen.add(alice);
    }
    expect(seen, hasLength(2), reason: 'both orders show up over 20 runs');
  });
}
