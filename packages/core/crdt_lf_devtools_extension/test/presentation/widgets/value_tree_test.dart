// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/presentation/widgets/handler_names.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/value_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Object? node, {
    ValueChanged<String>? onRef,
    Map<String, String> names = const {},
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HandlerNames(
          names: names,
          child: SingleChildScrollView(child: ValueTree(node, onRef: onRef)),
        ),
      ),
    ),
  );

  Finder rich(String text) => find.textContaining(text, findRichText: true);

  testWidgets('a value with many nested rows starts with one level', (
    tester,
  ) async {
    Object list(int maps) => {
      r'$t': 'list',
      'length': maps,
      'items': [
        for (var i = 0; i < maps; i++)
          {
            r'$t': 'map',
            'length': 10,
            'entries': [
              for (var f = 0; f < 10; f++) ['f$f', i],
            ],
          },
      ],
    };
    await pump(tester, list(20));
    expect(find.text('f0: '), findsNWidgets(20));

    // The same tree, grown past the limit.
    await pump(tester, list(21));
    expect(find.text('f0: '), findsNothing);
    expect(find.text('map · 10 entries'), findsNWidgets(21));
    await tester.tap(find.text('map · 10 entries').first);
    await tester.pump();
    expect(find.text('f0: '), findsOneWidget);

    // A tap holds over a new value.
    await pump(tester, list(22));
    expect(find.text('f0: '), findsOneWidget);
  });

  testWidgets('the rows of sets and objects count too', (tester) async {
    Object set(int items) => {
      r'$t': 'set',
      'length': items,
      'items': [for (var i = 0; i < items; i++) i],
    };
    for (final (value, title) in [
      (
        {
          r'$t': 'set',
          'length': 1,
          'items': [set(201)],
        },
        'set · 201 items',
      ),
      (
        {
          r'$t': 'list',
          'length': 1,
          'items': [set(201)],
        },
        'set · 201 items',
      ),
      ({r'$t': 'object', 'type': 'Point', 'json': set(201)}, 'set · 201 items'),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await pump(tester, value);
      expect(find.text(title), findsOneWidget);
      // At most the row of the nested set itself.
      expect(find.text('•: ').evaluate().length, lessThan(2));
    }
  });

  testWidgets('scalars and the non-finite double', (tester) async {
    await pump(tester, 7);
    expect(find.text('7'), findsOneWidget);
    await pump(tester, null);
    expect(find.text('null'), findsOneWidget);
    await pump(tester, {r'$t': 'double', 'v': 'NaN'});
    expect(find.text('NaN'), findsOneWidget);
  });

  testWidgets('a string, whole and cut', (tester) async {
    await pump(tester, 'hello');
    expect(rich('"hello"'), findsOneWidget);
    expect(rich('length 5'), findsOneWidget);

    await pump(tester, {r'$t': 'string', 'length': 12, 'head': 'abc'});
    expect(rich('"abc'), findsOneWidget);
    expect(find.text('… 9 more'), findsOneWidget);
  });

  testWidgets('a list with its indexes and the rest', (tester) async {
    await pump(tester, {
      r'$t': 'list',
      'length': 3,
      'items': ['a', 'b'],
    });
    expect(find.text('list · 3 items'), findsOneWidget);
    expect(find.text('[1]: '), findsOneWidget);
    expect(find.text('… 1 more'), findsOneWidget);
  });

  testWidgets('a set', (tester) async {
    await pump(tester, {
      r'$t': 'set',
      'length': 1,
      'items': [1],
    });
    expect(find.text('set · 1 items'), findsOneWidget);
    expect(find.text('•: '), findsOneWidget);
  });

  testWidgets('a map: scalar keys inline, other keys as a node', (
    tester,
  ) async {
    await pump(tester, {
      r'$t': 'map',
      'length': 2,
      'entries': [
        ['k', 4],
        [
          {r'$t': 'list', 'length': 0, 'items': <Object?>[]},
          true,
        ],
      ],
    });
    expect(find.text('map · 2 entries'), findsOneWidget);
    expect(find.text('k: '), findsOneWidget);
    expect(find.text('key: '), findsOneWidget);
    expect(find.text('true'), findsOneWidget);
  });

  testWidgets('a ref calls onRef', (tester) async {
    String? tapped;
    await pump(tester, {
      r'$t': 'ref',
      'id': 'child',
      'type': 'CRDTTextHandler',
    }, onRef: (id) => tapped = id);
    await tester.tap(find.text('→ child'));
    expect(tapped, 'child');
    expect(find.text('(CRDTTextHandler)'), findsOneWidget);
  });

  testWidgets('a ref shows the debug name and wraps when narrow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const id = 'd2907f93-d486-4b6d-a74b-7748d9e4f227';
    await pump(
      tester,
      {
        r'$t': 'map',
        'length': 2,
        'entries': [
          [
            'title',
            {r'$t': 'ref', 'id': 'child', 'type': 'CRDTFugueTextHandler'},
          ],
          [
            'paragraphs',
            {r'$t': 'ref', 'id': id, 'type': 'CRDTMovableListRefHandler'},
          ],
        ],
      },
      names: const {'child': 'title text'},
    );
    expect(tester.takeException(), isNull);
    expect(find.text('→ title text'), findsOneWidget);
    expect(find.text('→ $id'), findsOneWidget);
  });

  testWidgets('a span with attributes and an embed', (tester) async {
    await pump(tester, {
      r'$t': 'span',
      'text': 'Rich',
      'attributes': {
        r'$t': 'map',
        'length': 1,
        'entries': [
          ['bold', true],
        ],
      },
      'embed': {
        r'$t': 'map',
        'length': 1,
        'entries': [
          ['src', 'a.png'],
        ],
      },
    });
    expect(find.text('"Rich"'), findsOneWidget);
    expect(find.text('bold: true'), findsOneWidget);
    expect(find.text('embed: '), findsOneWidget);
    expect(rich('"a.png"'), findsOneWidget);
  });

  testWidgets('a span with a cut text', (tester) async {
    await pump(tester, {
      r'$t': 'span',
      'text': {r'$t': 'string', 'length': 12, 'head': 'abc'},
      'attributes': {r'$t': 'map', 'length': 0, 'entries': <Object?>[]},
      'embed': null,
    });
    expect(rich('"abc'), findsOneWidget);
    expect(find.text('… 9 more'), findsOneWidget);
  });

  testWidgets('bytes', (tester) async {
    await pump(tester, {r'$t': 'bytes', 'length': 40, 'head': '00ff'});
    expect(find.text('bytes · length 40'), findsOneWidget);
    expect(find.text('00ff'), findsOneWidget);
    expect(find.text('… 38 more'), findsOneWidget);
  });

  testWidgets('an object, with and without json', (tester) async {
    await pump(tester, {r'$t': 'object', 'type': 'Point', 'text': 'P(1)'});
    expect(find.text('Point'), findsOneWidget);
    expect(find.text('P(1)'), findsOneWidget);

    await pump(tester, {
      r'$t': 'object',
      'type': 'Point',
      'text': 'P(1)',
      'json': 1,
    });
    expect(find.text('P(1)'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a node past the depth limit', (tester) async {
    await pump(tester, {r'$t': 'more'});
    expect(find.text('… deeper levels not loaded'), findsOneWidget);
  });

  testWidgets('nodes below depth 2 start collapsed', (tester) async {
    Object list(Object? item) => {
      r'$t': 'list',
      'length': 1,
      'items': [item],
    };
    await pump(tester, list(list(list('deep'))));
    expect(find.text('list · 1 items'), findsNWidgets(3));
    expect(rich('"deep"'), findsNothing);

    await tester.tap(find.text('list · 1 items').last);
    await tester.pump();
    expect(rich('"deep"'), findsOneWidget);
  });
}
