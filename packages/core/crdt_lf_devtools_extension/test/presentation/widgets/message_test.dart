// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/presentation/widgets/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a retry button only with onRetry', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            const PaneMessage('plain'),
            PaneMessage('failed', onRetry: () => retries++),
          ],
        ),
      ),
    );
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('a banner shows a retry button only with onRetry', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const MessageBanner('plain'),
              MessageBanner('failed', onRetry: () => retries++),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  test('the loading line of the changes', () {
    expect(PaneMessage.loadingChanges(null).text, 'Loading changes…');
    expect(
      PaneMessage.loadingChanges((loaded: 1000, total: 10000)).text,
      'Loading changes 1000 / 10000',
    );
  });
}
