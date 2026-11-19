// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/presentation/widgets/keyboard_list.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('up and down move the selection and scroll to it', (
    tester,
  ) async {
    int? selected;
    final picked = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 5 * defaultRowHeight,
                child: KeyboardList(
                  itemCount: 50,
                  itemBuilder: (context, i) => Text('row $i'),
                  selectedIndex: () => selected,
                  // Row 1 is a title row.
                  canSelect: (i) => i != 1,
                  onSelect: (i) {
                    selected = i;
                    picked.add(i);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // The keys reach the list only once a tap gives it the focus.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(picked, isEmpty);
    await tester.tap(find.text('row 3'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(selected, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(selected, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(selected, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(selected, 0, reason: 'the first row stays selected');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(picked, [0, 2, 0]);

    selected = 48;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('row 49'), findsOneWidget);
    expect(find.text('row 0'), findsNothing);

    selected = 3;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(selected, 2);
    expect(find.text('row 2'), findsOneWidget);
  });
}
