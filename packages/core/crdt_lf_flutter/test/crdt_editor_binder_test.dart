// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrdtEditorBinder', () {
    late CRDTDocument doc;
    late List<RichTextSpan> spans;
    late CrdtEditorBinding<List<RichTextSpan>, RichTextDelta> binding;
    var builds = 0;
    var checks = 0;

    Widget host({String id = 'a'}) {
      return CrdtProvider.value(
        value: doc,
        child: MaterialApp(
          home: CrdtEditorBinder<List<RichTextSpan>, RichTextDelta>(
            id: id,
            onRemoteDelta: (event) => spans = event.delta.apply(spans),
            onReset: (value, cause) => spans = value,
            verifyProjection: () {
              checks++;
              return true;
            },
            deletedBuilder: (context) => const Text('deleted'),
            builder: (context, value) {
              builds++;
              binding = value;
              return const SizedBox();
            },
          ),
        ),
      );
    }

    setUp(() {
      doc = CRDTDocument(peerId: PeerId.generate());
      spans = [];
      builds = 0;
      checks = 0;
    });

    testWidgets('builds once while the handler moves both ways',
        (tester) async {
      final a = CRDTFugueRichTextHandler(doc, 'a')..insert(0, 'hello');
      await tester.pumpWidget(host());
      expect(spans, a.value);

      a.insert(5, ' world', attributes: {'bold': true});
      spans =
          RichTextDelta([RichTextRetain(0), RichTextInsert('> ')]).apply(spans);
      binding.push(() => a.insert(0, '> '));
      await tester.pump();

      expect(spans, a.value);
      expect(checks, greaterThan(0));
      expect(builds, 1);
    });

    testWidgets('follows the handler when the id changes', (tester) async {
      CRDTFugueRichTextHandler(doc, 'a').insert(0, 'first');
      final b = CRDTFugueRichTextHandler(doc, 'b')..insert(0, 'second');
      await tester.pumpWidget(host());
      await tester.pumpWidget(host(id: 'b'));
      expect(spans, b.value);

      b.insert(0, 'the ');
      expect(spans, b.value);
    });

    testWidgets('shows deletedBuilder once the handler is deleted',
        (tester) async {
      final a = CRDTFugueRichTextHandler(doc, 'a')..insert(0, 'hello');
      await tester.pumpWidget(host());

      doc.deleteHandler(a);
      await tester.pump();

      expect(find.text('deleted'), findsOneWidget);
      expect(binding.isAttached, isFalse);
    });
  });
}
