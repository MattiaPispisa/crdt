// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps until [done] holds.
///
/// Between two pumps the real IO (sockets, Hive) and [poll] run, and the fake
/// time moves by [step].
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration step = Duration.zero,
  Future<void> Function()? poll,
}) async {
  var rounds = 0;
  do {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await poll?.call();
    });
    await tester.pump(step);
  } while (!done() && ++rounds < 200);
  expect(done(), isTrue);
}

/// Waits until [text], in [document], reads [expected].
Future<void> waitForText(
  CRDTDocument document,
  CRDTFugueTextHandler text,
  String expected,
) async {
  if (text.value == expected) return;
  await document.updates
      .firstWhere((_) => text.value == expected)
      .timeout(const Duration(seconds: 5));
}

/// Sends to each document what the other is missing.
void exchange(CRDTDocument a, CRDTDocument b) {
  a.importChanges(b.exportChanges());
  b.importChanges(a.exportChanges());
}
