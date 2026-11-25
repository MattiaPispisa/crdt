// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/main_demo.dart' as demo;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(DevToolsBridge.reset);
  tearDown(DevToolsBridge.reset);

  testWidgets('the demo starts and adds 10 000 changes', (tester) async {
    demo.main();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('12 handlers'), findsOneWidget);
    expect(find.text('0 changes'), findsOneWidget);

    await tester.tap(find.text('10 000 changes'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('10000 changes'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
