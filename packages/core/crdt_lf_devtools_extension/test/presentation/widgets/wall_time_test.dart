// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/presentation/widgets/wall_time.dart';
import 'package:flutter_test/flutter_test.dart';

// A UTC time in a zone one hour ahead, whatever the zone of the machine.
class _Utc extends Fake implements DateTime {
  @override
  DateTime toLocal() => DateTime(2026, 1, 2, 10, 5, 3, 42);
}

void main() {
  test('shows the local time', () {
    expect(wallTime(_Utc()), '10:05:03.042');
  });
}
