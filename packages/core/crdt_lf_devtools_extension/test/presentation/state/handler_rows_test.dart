// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/state/handler_rows.dart';
import 'package:flutter_test/flutter_test.dart';

HandlerSummary _handler(String id, [List<String> children = const []]) =>
    HandlerSummary(
      id: id,
      type: children.isEmpty ? 'CRDTTextHandler' : 'CRDTMapRefHandler',
      container: children.isNotEmpty,
      children: [
        for (final c in children) HandlerInfo(id: c, type: 'CRDTTextHandler'),
      ],
      changeCount: 0,
      revision: 0,
      cache: HandlerCache.none,
      pendingRemote: 0,
      deltas: true,
      watched: false,
      deltaSeq: 0,
      invertible: true,
      undoTracked: false,
      snapshotBytes: null,
    );

List<String> _open(List<HandlerRow> rows) => [
  for (final row in rows)
    if (row case OpenRow(:final handler, :final depth))
      '${'  ' * depth}${handler.id}',
];

void main() {
  test('a child sits under each container that lists it', () {
    final list = HandlerList(
      open: [
        _handler('a', ['shared']),
        _handler('b', ['shared', 'not-open']),
        _handler('shared'),
      ],
      closed: const [],
      deleted: const [],
    );
    expect(_open(handlerRows(list)), ['a', '  shared', 'b', '  shared']);
  });

  test('a cycle is drawn once per path and its handlers stay listed', () {
    final list = HandlerList(
      open: [
        _handler('x', ['y']),
        _handler('y', ['x']),
      ],
      closed: const [],
      deleted: const [],
    );
    expect(_open(handlerRows(list)), ['x', '  y']);
  });

  test('the filter keeps the ancestors of a match', () {
    final list = HandlerList(
      open: [
        _handler('root', ['leaf']),
        _handler('leaf'),
        _handler('other'),
      ],
      closed: const [ClosedHandler(id: 'leaf-old', type: null, changeCount: 1)],
      deleted: const ['leaf-gone', 'x'],
    );
    final rows = handlerRows(
      list,
      filter: ' LEAF ',
      closedExpanded: true,
      deletedExpanded: true,
    );
    expect(_open(rows), ['root', '  leaf']);
    expect(rows.whereType<ClosedRow>().map((r) => r.id), ['leaf-old']);
    expect(rows.whereType<DeletedRow>().map((r) => r.id), ['leaf-gone']);
    expect([for (final g in rows.whereType<GroupRow>()) g.count], [2, 1, 1]);
  });

  test('closed and deleted are collapsed by default', () {
    const list = HandlerList(
      open: [],
      closed: [ClosedHandler(id: 'c', type: 'T', changeCount: 1)],
      deleted: ['d'],
    );
    final rows = handlerRows(list);
    expect(rows.whereType<GroupRow>().map((g) => g.expanded), [
      true,
      false,
      false,
    ]);
    expect(rows.length, 3);
  });
}
