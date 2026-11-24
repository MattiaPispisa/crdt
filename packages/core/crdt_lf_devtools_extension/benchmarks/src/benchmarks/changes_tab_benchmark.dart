// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/change_row.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../common/fixture.dart';

/// One edit shown by the open Changes tab, on a document of [handlers]
/// handlers.
class ChangesTabEditBenchmark extends AsyncFixedCycleTimedBenchmark {
  ChangesTabEditBenchmark(this.tester, this.handlers)
    : super(
        'Edit with the Changes tab open, $handlers handlers',
        measuredCycles: 10,
        batches: 3,
        setupPerBatch: false,
      );

  final WidgetTester tester;

  final int handlers;

  late CRDTDocument _doc;

  @override
  Future<void> setup() async {
    resetBridge();
    _doc = mapDocument(1);
    for (var i = 1; i < handlers; i++) {
      CRDTTextHandler(_doc, 'text $i').insert(0, 'x');
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CrdtLfScreen(bridge: InProcessBridge())),
      ),
    );
    await _settle();
    await tester.tap(find.widgetWithText(Tab, 'Changes'));
    await _settle();
    await _settle();
    if (find.byType(ChangeRow).evaluate().isEmpty) {
      throw StateError('The Changes tab shows no data');
    }
  }

  // Past the reload gates and the frame after.
  Future<void> _settle() async {
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  @override
  Future<void> run() async {
    edit(_doc);
    await _settle();
  }

  @override
  Future<void> teardown() async {
    await tester.pumpWidget(const SizedBox.shrink());
    _doc.dispose();
    resetBridge();
  }
}

void main() {
  testWidgets(
    'changes tab',
    (tester) async {
      for (final handlers in [10, 1000, 5000]) {
        await ChangesTabEditBenchmark(tester, handlers).report();
      }
    },
    // The tab animation moves a search field past the screen edge, and the
    // semantics check fails on it: the benchmark measures no semantics.
    semanticsEnabled: false,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
