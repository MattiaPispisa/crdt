// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_examples_infrastructure/examples/document/_state.dart';

void main() {
  group('DocumentExampleState', () {
    late CRDTDocument document;
    late DocumentExampleState state;

    setUp(() {
      document = CRDTDocument(peerId: PeerId.generate());
      state =
          DocumentExampleState(document)
            ..addChapter('a')
            ..addChapter('b')
            ..addChapter('c');
    });

    test('indexes count the chapters it shows, not the references', () {
      final [a, b, c] = state.chapters;
      // As a peer's delete leaves it: the reference stays in the list.
      document.deleteHandler(b);

      state.removeChapter(1);

      expect(document.isDeleted(c.id), isTrue);
      expect(state.chapters, [a]);
    });

    test('reorders the chapters it shows', () {
      final [a, b, c] = state.chapters;
      document.deleteHandler(b);

      state.reorderChapters(1, 0);

      expect(state.chapters, [c, a]);
    });
  });
}
