// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/widgets/select.dart';

void main() {
  group('Select', () {
    testWidgets('opens its menu below the field, as wide as the field', (
      tester,
    ) async {
      int? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: Select<int>(
                  value: 1,
                  options: const [
                    SelectOption(value: 1, label: 'one'),
                    SelectOption(value: 2, label: 'two'),
                  ],
                  onChanged: (value) => picked = value,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsNothing);

      final field = tester.getRect(find.byType(Select<int>));
      await tester.tap(find.byType(Select<int>));
      await tester.pumpAndSettle();

      final menu = tester.getRect(find.byType(PopupMenuItem<int>).first);
      expect(menu.width, field.width);
      expect(menu.top, greaterThanOrEqualTo(field.bottom));

      await tester.tap(find.text('two'));
      await tester.pumpAndSettle();
      expect(picked, 2);
    });
  });
}
