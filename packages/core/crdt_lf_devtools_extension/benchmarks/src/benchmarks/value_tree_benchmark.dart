// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/value_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One change of the value of a [ValueTree]: a list of [maps] maps of
/// [fields] fields each, as a handler the app keeps editing.
///
/// With [grown], the tree first shows the same maps with one field.
class ValueChangeBenchmark extends AsyncFixedCycleTimedBenchmark {
  ValueChangeBenchmark(
    this.tester, {
    required this.maps,
    required this.fields,
    this.grown = false,
  }) : super(
         'Value change, $maps maps of $fields fields'
         '${grown ? ', grown from 1' : ''}',
         measuredCycles: 5,
         batches: 3,
         setupPerBatch: false,
       );

  final WidgetTester tester;

  final int maps;

  final int fields;

  final bool grown;

  var _version = 0;

  Object _value(int fields) => {
    r'$t': 'list',
    'length': maps,
    'items': [
      for (var i = 0; i < maps; i++)
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
  Future<void> setup() => _show(grown ? 1 : fields);

  @override
  Future<void> run() => _show(fields);

  Future<void> _show(int fields) {
    _version++;
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            child: SingleChildScrollView(child: ValueTree(_value(fields))),
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
      for (final benchmark in [
        ValueChangeBenchmark(tester, maps: 20, fields: 10),
        ValueChangeBenchmark(tester, maps: 200, fields: 5),
        ValueChangeBenchmark(tester, maps: 200, fields: 20),
        ValueChangeBenchmark(tester, maps: 20, fields: 200, grown: true),
      ]) {
        await benchmark.report();
        await tester.pumpWidget(const SizedBox());
      }
    },
    semanticsEnabled: false,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
