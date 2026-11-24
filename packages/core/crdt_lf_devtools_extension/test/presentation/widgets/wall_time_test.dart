// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/presentation/widgets/wall_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shows the local time of a UTC time', () {
    final local = DateTime(2026, 1, 2, 9, 5, 3, 42);
    expect(wallTime(local.toUtc()), '09:05:03.042');
  });
}
