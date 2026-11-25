// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf_devtools_extension/src/bridge/reload_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_time.dart';

void main() {
  const delay = Duration(seconds: 1);
  const tick = Duration(milliseconds: 1);

  testOnFakeTime('a burst gives one load, after the delay', (tester) async {
    var loads = 0;
    final gate = ReloadGate(() async => loads++, delay: delay);

    var served = 0;
    for (var i = 0; i < 10; i++) {
      unawaited(gate.request().then((_) => served++));
      await tester.pump(tick);
    }
    // The delay counts from the first request.
    await tester.pump(delay - tick * 11);
    expect(loads, 0);
    await tester.pump(tick);
    expect(loads, 1);
    expect(served, 10);

    await tester.pump(delay * 10);
    expect(loads, 1);
  });

  testOnFakeTime('a request during a load gives exactly one more', (
    tester,
  ) async {
    var loads = 0;
    final release = Completer<void>();
    final gate = ReloadGate(() async {
      loads++;
      if (loads == 1) await release.future;
    }, delay: delay);
    var first = false;
    unawaited(gate.request().then((_) => first = true));
    await tester.pump(delay);
    expect(loads, 1);

    var during = 0;
    for (var i = 0; i < 2; i++) {
      unawaited(gate.request().then((_) => during++));
    }
    // Not next to the running one, however long it takes.
    await tester.pump(delay * 10);
    expect((loads, first, during), (1, false, 0));

    release.complete();
    await tester.pump(delay - tick);
    expect((loads, first, during), (1, true, 0));
    await tester.pump(tick);
    expect((loads, during), (2, 2));

    await tester.pump(delay * 10);
    expect(loads, 2);
  });

  testOnFakeTime('a failed load reaches the caller, and the next one runs', (
    tester,
  ) async {
    var loads = 0;
    final gate = ReloadGate(() async {
      if (++loads == 1) throw StateError('x');
    }, delay: delay);

    Object? error;
    unawaited(gate.request().catchError((Object e) => error = e));
    await tester.pump(delay);
    expect(error, isStateError);

    var served = false;
    unawaited(gate.request().then((_) => served = true));
    await tester.pump(delay);
    expect((loads, served), (2, true));
  });

  testOnFakeTime('dispose drops the waiting load and frees its callers', (
    tester,
  ) async {
    var loads = 0;
    final gate = ReloadGate(() async => loads++, delay: delay);
    var served = 0;
    unawaited(gate.request().then((_) => served++));

    gate.dispose();
    unawaited(gate.request().then((_) => served++));
    // No time passes: a timer still alive here fails the test.
    await tester.pump();
    expect((loads, served), (0, 2));
  });

  testOnFakeTime('dispose during a load runs no other one', (tester) async {
    var loads = 0;
    final release = Completer<void>();
    final gate = ReloadGate(() async {
      loads++;
      await release.future;
    }, delay: delay);
    var served = 0;
    unawaited(gate.request().then((_) => served++));
    await tester.pump(delay);
    unawaited(gate.request().then((_) => served++));

    gate.dispose();
    release.complete();
    await tester.pump(delay * 10);
    expect((loads, served), (1, 2));
  });
}
