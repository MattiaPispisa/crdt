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

/// Leaves the [tab] for the Events tab, which loads nothing, and comes
/// back, on a document of [size] changes, until the tab shows its data
/// again.
class TabSwitchBenchmark extends AsyncFixedCycleTimedBenchmark {
  TabSwitchBenchmark(this.tester, this.tab, this.size)
    : super(
        'Back to the $tab tab, $size changes',
        measuredCycles: 5,
        batches: 3,
        setupPerBatch: false,
      );

  final WidgetTester tester;

  final String tab;

  final int size;

  late CRDTDocument _doc;

  @override
  Future<void> setup() async {
    resetBridge();
    _doc = mapDocument(size);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CrdtLfScreen(bridge: InProcessBridge())),
      ),
    );
    await _settle();
    await _open(tab);
  }

  // Past the reload gates, the tab animation and the frame after.
  Future<void> _settle() async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> _open(String tab) async {
    await tester.tap(find.widgetWithText(Tab, tab));
    await _settle();
  }

  @override
  Future<void> run() async {
    await _open('Events');
    await _open(tab);
    // A failed or slower load must not pass as a fast one.
    final loaded =
        tab == 'Changes' ? find.byType(ChangeRow) : find.byType(Slider);
    if (loaded.evaluate().isEmpty) {
      throw StateError('The $tab tab shows no data');
    }
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
    'tab switch',
    (tester) async {
      for (final size in [10000, 50000]) {
        for (final tab in ['Changes', 'Time travel']) {
          await TabSwitchBenchmark(tester, tab, size).report();
        }
      }
    },
    // The tab animation moves a search field past the screen edge, and the
    // semantics check fails on it: the benchmark measures no semantics.
    semanticsEnabled: false,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
