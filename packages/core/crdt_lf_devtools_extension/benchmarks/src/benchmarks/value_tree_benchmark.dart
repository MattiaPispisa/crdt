// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/value_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One change of the value of a [ValueTree]: a list of 200 maps of [fields]
/// fields each, as a handler the app keeps editing.
class ValueChangeBenchmark extends AsyncFixedCycleTimedBenchmark {
  ValueChangeBenchmark(this.tester, this.fields)
    : super(
        'Value change, 200 maps of $fields fields',
        measuredCycles: 5,
        batches: 3,
        setupPerBatch: false,
      );

  final WidgetTester tester;

  final int fields;

  var _version = 0;

  Object _value() => {
    r'$t': 'list',
    'length': 200,
    'items': [
      for (var i = 0; i < 200; i++)
        {
          r'$t': 'map',
          'length': fields,
          'entries': [
            for (var f = 0; f < fields; f++) ['f$f', _version + i],
          ],
        },
    ],
  };

  @override
  Future<void> run() {
    _version++;
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: SingleChildScrollView(child: ValueTree(_value())),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
    'value tree',
    (tester) async {
      for (final fields in [5, 20]) {
        await ValueChangeBenchmark(tester, fields).report();
        await tester.pumpWidget(const SizedBox());
      }
    },
    semanticsEnabled: false,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
