// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/application/changes/list_views.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a prefix keeps its length while the list grows', () {
    final source = [1, 2, 3];
    final prefix = PrefixView(source, 2);
    source.add(4);

    expect(prefix, [1, 2]);
    expect(() => prefix[2], throwsRangeError);
    expect(() => prefix[0] = 9, throwsUnsupportedError);
    expect(() => prefix.add(9), throwsUnsupportedError);
  });

  test('a reversed view reads the list from its end', () {
    final reversed = ReversedView([1, 2, 3]);

    expect(reversed, [3, 2, 1]);
    expect(() => reversed[3], throwsRangeError);
    expect(() => reversed[0] = 9, throwsUnsupportedError);
    expect(() => reversed.length = 0, throwsUnsupportedError);
  });
}
