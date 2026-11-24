// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../common/fixture.dart';

const _documents = 20;

/// An edit of one of [_documents] documents while a [DocumentsCubit] lists
/// them, until the extension is idle again.
class DocumentEditBenchmark extends AsyncFixedCycleTimedBenchmark {
  DocumentEditBenchmark({required this.selected})
    : super(
        'Edit of ${selected ? 'the selected' : 'another'} document, '
        '$_documents documents',
        measuredCycles: 100,
        setupPerBatch: false,
      );

  final bool selected;

  late List<CRDTDocument> _docs;

  late Extension _extension;

  late DocumentsCubit _cubit;

  late CRDTDocument _edited;

  @override
  Future<void> setup() async {
    resetBridge();
    _docs = [
      for (var i = 0; i < _documents; i++) mapDocument(100, documentId: 'd$i'),
    ];
    _extension = Extension();
    _cubit = DocumentsCubit(_extension.client, delay: Duration.zero);
    await settle();
    final selectedId = _cubit.state.selectedId;
    _edited = _docs.firstWhere(
      (d) =>
          (_cubit.state.documents
                  .firstWhere((s) => s.documentId == d.documentId)
                  .id ==
              selectedId) ==
          selected,
    );
  }

  @override
  Future<void> run() async {
    edit(_edited);
    await settle();
  }

  @override
  Future<void> teardown() async {
    await _cubit.close();
    _extension.dispose();
    for (final doc in _docs) {
      doc.dispose();
    }
    resetBridge();
  }
}

void main() {
  test('documents', () async {
    for (final selected in [true, false]) {
      await DocumentEditBenchmark(selected: selected).report();
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}
