// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_quill_example/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('text typed by Alice shows up in Bob', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const QuillExampleApp());

    final editors = find.byType(QuillEditor);
    final alice = tester.widget<QuillEditor>(editors.first).controller;
    final bob = tester.widget<QuillEditor>(editors.last).controller;

    await tester.tap(editors.first);
    await tester.pump();
    // Quill's editing value always ends with its own newline.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Hello\n',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    expect(alice.document.toPlainText(), 'Hello\n');
    expect(bob.document.toPlainText(), 'Hello\n');

    // Let the editors' timers run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
