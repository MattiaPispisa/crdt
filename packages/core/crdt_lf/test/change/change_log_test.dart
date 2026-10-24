// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/change/change_log.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';

void main() {
  group('ChangeLog', () {
    test('sortTopologically puts dependencies first', () {
      final author = PeerId.generate();
      final operation = TestOperation.fromHandler(TestHandler(CRDTDocument()));
      Change change(int counter, Set<OperationId> deps) => Change(
            id: OperationId(author, HybridLogicalClock(l: 1, c: counter)),
            operation: operation,
            deps: deps,
            author: author,
          );
      final first = change(1, {});
      final second = change(2, {first.id});
      final third = change(3, {second.id});

      expect(
        ChangeLog.sortTopologically([third, second, first]),
        [first, second, third],
      );
    });
  });
}
