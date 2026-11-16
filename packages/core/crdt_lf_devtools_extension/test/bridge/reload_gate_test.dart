// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf_devtools_extension/src/bridge/reload_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const delay = Duration(milliseconds: 5);

  test('a burst gives one load', () async {
    var loads = 0;
    final gate = ReloadGate(() async => loads++, delay: delay);

    await Future.wait([for (var i = 0; i < 10; i++) gate.request()]);

    expect(loads, 1);
    gate.dispose();
  });

  test('a request during a load gives exactly one more', () async {
    var loads = 0;
    var release = Completer<void>();
    final gate = ReloadGate(() async {
      loads++;
      await release.future;
    }, delay: delay);

    final first = gate.request();
    await Future<void>.delayed(delay * 4);
    expect(loads, 1);
    final during = [gate.request(), gate.request()];
    release.complete();
    await first;
    release = Completer<void>()..complete();
    await Future.wait(during);

    expect(loads, 2);
    gate.dispose();
  });

  test('a failed load reaches the caller', () async {
    final gate = ReloadGate(() async => throw StateError('x'), delay: delay);

    await expectLater(gate.request(), throwsStateError);
    gate.dispose();
  });
}
