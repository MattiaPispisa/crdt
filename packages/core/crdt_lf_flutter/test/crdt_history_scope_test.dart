// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _todos(String label) => CrdtHandlerBuilder<CRDTListHandler<String>>(
      id: 'todos',
      builder: (context, handler) => Text(
        '$label:${handler.value.join(',')}',
        textDirection: TextDirection.ltr,
      ),
    );

void main() {
  group('CrdtHistoryScope', () {
    testWidgets('draws the frozen document with the live widgets',
        (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final todos = CRDTListHandler<String>(
        doc,
        'todos',
        handlerType: 'CRDTListHandler<String>',
      )
        ..insert(0, 'a')
        ..insert(1, 'b');

      late HistorySession session;
      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: Column(
            textDirection: TextDirection.ltr,
            children: [
              _todos('live'),
              CrdtHistoryScope(
                builder: (context, s) {
                  session = s;
                  return _todos('past');
                },
              ),
            ],
          ),
        ),
      );
      expect(find.text('live:a,b'), findsOneWidget);
      expect(find.text('past:a,b'), findsOneWidget);

      session.previous();
      await tester.pumpAndSettle();
      expect(find.text('past:a'), findsOneWidget);
      expect(find.text('live:a,b'), findsOneWidget);

      // The view is a snapshot: a later edit reaches the live tree only.
      todos.insert(2, 'c');
      await tester.pumpAndSettle();
      expect(find.text('live:a,b,c'), findsOneWidget);
      expect(find.text('past:a'), findsOneWidget);

      session.jump(0);
      await tester.pumpAndSettle();
      expect(find.text('past:'), findsOneWidget);
    });

    testWidgets('a write on the view throws, the live tree is not touched',
        (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(
        doc,
        'todos',
        handlerType: 'CRDTListHandler<String>',
      ).insert(0, 'a');

      late BuildContext inside;
      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: CrdtHistoryScope(
            builder: (context, _) {
              inside = context;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(
        () => inside.crdtHandler<CRDTListHandler<String>>('todos').insert(1, 'x'),
        throwsA(isA<ReadOnlyDocumentException>()),
      );
      expect(
        (doc.registeredHandlers['todos']! as CRDTListHandler<String>).value,
        ['a'],
      );
    });

    testWidgets('a delta builder shows the value at the cursor', (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final todos = CRDTListHandler<String>(
        doc,
        'todos',
        handlerType: 'CRDTListHandler<String>',
      )
        ..insert(0, 'a')
        ..insert(1, 'b');

      late HistorySession session;
      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: CrdtHistoryScope(
            builder: (context, s) {
              session = s;
              return CrdtHandlerDeltaBuilder<List<String>,
                  SequenceDelta<String>>(
                id: 'todos',
                builder: (context, value) => Text(
                  'past:${value.join(',')}',
                  textDirection: TextDirection.ltr,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('past:a,b'), findsOneWidget);

      session.previous();
      await tester.pumpAndSettle();
      expect(find.text('past:a'), findsOneWidget);

      // The live document moves on; the view does not.
      todos.insert(2, 'c');
      await tester.pumpAndSettle();
      expect(find.text('past:a'), findsOneWidget);

      session.jump(0);
      await tester.pumpAndSettle();
      expect(find.text('past:'), findsOneWidget);
    });

    testWidgets('the widgets that need the live document refuse the scope',
        (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final inScope = <Widget>[
        CrdtBuilder(builder: (context, document) => const SizedBox()),
        CrdtSelector<int>(
          selector: (context, document) => 0,
          builder: (context, value) => const SizedBox(),
        ),
        CrdtTextFieldBuilder(
          id: 'note',
          builder: (context, controller) => const SizedBox(),
        ),
        const CrdtTextCursorsOverlay(
          id: 'note',
          cursors: [],
          child: SizedBox(),
        ),
      ];

      for (final widget in inScope) {
        await tester.pumpWidget(
          CrdtProvider.value(
            value: doc,
            child: CrdtHistoryScope(builder: (context, _) => widget),
          ),
        );
        expect(
          tester.takeException(),
          isA<FlutterError>().having(
            (e) => e.message,
            'message',
            contains('cannot be used inside a CrdtHistoryScope'),
          ),
        );
      }
    });

    testWidgets('disposes the session with the widget', (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(
        doc,
        'todos',
        handlerType: 'CRDTListHandler<String>',
      ).insert(0, 'a');

      late HistorySession session;
      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: CrdtHistoryScope(
            builder: (context, s) {
              session = s;
              return _todos('past');
            },
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());

      expect(session.document.isDisposed, isTrue);
    });
  });
}
