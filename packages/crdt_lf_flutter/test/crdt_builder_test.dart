import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrdtBuilder', () {
    testWidgets('rebuilds on local and remote changes', (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final list = CRDTListHandler<String>(doc, 'list');

      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: MaterialApp(
            home: CrdtBuilder(
              builder: (context, document) => Text(
                list.value.join(','),
                textDirection: TextDirection.ltr,
              ),
            ),
          ),
        ),
      );
      expect(find.text(''), findsOneWidget);

      // Local edit.
      list.insert(0, 'a');
      await tester.pumpAndSettle();
      expect(find.text('a'), findsOneWidget);

      // Remote edit imported into the observed document.
      final remote = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(remote, 'list').insert(0, 'b');
      doc.importChanges(remote.exportChanges());
      await tester.pumpAndSettle();
      expect(list.value.contains('b'), isTrue);
    });
  });

  group('CrdtSelector', () {
    testWidgets('rebuilds only when the selected slice changes',
        (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final list = CRDTListHandler<Map<String, dynamic>>(doc, 'list');

      var builds = 0;
      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: MaterialApp(
            home: CrdtSelector<int>(
              selector: (context, document) => list.value.length,
              builder: (context, count) {
                builds++;
                return Text('$count', textDirection: TextDirection.ltr);
              },
            ),
          ),
        ),
      );
      expect(builds, 1);
      expect(find.text('0'), findsOneWidget);

      // Length changes -> rebuild.
      list.insert(0, {'text': 'a'});
      await tester.pumpAndSettle();
      expect(builds, 2);
      expect(find.text('1'), findsOneWidget);

      // Update in place (length unchanged) -> no rebuild.
      list.update(0, {'text': 'b'});
      await tester.pumpAndSettle();
      expect(builds, 2);
    });

    testWidgets('throws a FlutterError when the value type is dynamic',
        (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: MaterialApp(
            home: CrdtSelector<dynamic>(
              selector: (context, document) => document,
              builder: (context, value) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isFlutterError);
    });
  });
}
