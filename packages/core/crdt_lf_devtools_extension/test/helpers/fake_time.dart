// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:flutter_test/flutter_test.dart';

/// A test on fake time: `tester.pump` moves the timers of the extension and
/// the leases of the app together.
///
/// The body closes its cubits: no timer can be left at its end.
void testOnFakeTime(String description, WidgetTesterCallback body) =>
    testWidgets(description, (tester) async {
      DevToolsBridge.stopwatch = tester.binding.clock.stopwatch;
      addTearDown(() => DevToolsBridge.stopwatch = Stopwatch.new);
      await body(tester);
    });
