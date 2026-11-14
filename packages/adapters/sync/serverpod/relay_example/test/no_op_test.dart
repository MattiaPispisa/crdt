// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:test/test.dart';

/// `main_test.dart` is `@TestOn('vm')` (it opens a real socket), and
/// a Chrome run with nothing in it fails.
void main() {
  test('no-op', () {
    expect(() {}, returnsNormally);
  });
}
