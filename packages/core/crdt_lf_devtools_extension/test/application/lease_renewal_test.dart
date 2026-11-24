// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/application/lease_renewal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renews until stopped and reports a stopped lease', () async {
    var missed = 0;
    final answers = [true, false, true];
    final renewal = LeaseRenewal(
      every: const Duration(milliseconds: 10),
      onMissed: () => missed++,
    );
    var calls = 0;
    renewal.start(() async {
      final answer = answers[calls % answers.length];
      calls++;
      if (calls == 2) throw StateError('a failed call');
      return answer;
    });
    await Future<void>.delayed(const Duration(milliseconds: 65));
    renewal.stop();
    final stopped = calls;
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(stopped, greaterThanOrEqualTo(4));
    expect(calls, stopped);
    expect(missed, greaterThan(0));
  });
}
