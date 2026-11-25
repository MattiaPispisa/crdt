// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/application/lease_renewal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // `testWidgets` runs on fake time: each pump fires the due timers.
  testWidgets('renews until stopped and reports a stopped lease', (
    tester,
  ) async {
    var missed = 0;
    final answers = <Object>[true, StateError('a failed call'), false];
    var calls = 0;
    final renewal = LeaseRenewal(
      every: const Duration(seconds: 1),
      onMissed: () => missed++,
    )..start(() async {
      final answer = answers[calls++];
      if (answer is Error) throw answer;
      return answer as bool;
    });

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(calls, 3);
    expect(missed, 1);

    renewal.stop();
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 3);
  });
}
