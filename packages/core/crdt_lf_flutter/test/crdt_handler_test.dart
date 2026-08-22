import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrdtHandlerBuilder', () {
    testWidgets('rebuilds on its handler change but not on an unrelated one',
        (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final a = CRDTListHandler<String>(doc, 'a');
      final b = CRDTListHandler<String>(doc, 'b');

      var builds = 0;
      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: MaterialApp(
            home: CrdtHandlerBuilder<CRDTListHandler<String>>(
              id: 'a',
              builder: (context, handler) {
                builds++;
                return Text(
                  handler.value.join(','),
                  textDirection: TextDirection.ltr,
                );
              },
            ),
          ),
        ),
      );
      expect(builds, 1);

      // Editing the observed handler rebuilds.
      a.insert(0, 'x');
      await tester.pumpAndSettle();
      expect(builds, 2);
      expect(find.text('x'), findsOneWidget);

      // Editing an unrelated handler does NOT rebuild.
      b.insert(0, 'y');
      await tester.pumpAndSettle();
      expect(builds, 2);
    });

    testWidgets('rebuilds when a remote change for its handler is imported',
        (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(doc, 'a');

      var builds = 0;
      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: MaterialApp(
            home: CrdtHandlerBuilder<CRDTListHandler<String>>(
              id: 'a',
              builder: (context, handler) {
                builds++;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(builds, 1);

      final remote = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(remote, 'a').insert(0, 'r');
      doc.importChanges(remote.exportChanges());
      await tester.pumpAndSettle();
      expect(builds, 2);
    });

    testWidgets('rebuilds when a snapshot import changes its handler value',
        (tester) async {
      // Peer that produced a snapshot with content for handler "a".
      final source = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(source, 'a').insert(0, 'fromSnapshot');
      final snapshot = source.takeSnapshot();

      // Observed doc registers "a" with zero local changes.
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(doc, 'a');

      var builds = 0;
      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: MaterialApp(
            home: CrdtHandlerBuilder<CRDTListHandler<String>>(
              id: 'a',
              builder: (context, handler) {
                builds++;
                return Text(
                  handler.value.join(','),
                  textDirection: TextDirection.ltr,
                );
              },
            ),
          ),
        ),
      );
      expect(builds, 1);

      // changeCountForHandler('a') stays 0 here: the rebuild is driven by
      // revisionForHandler growing on the snapshot import.
      expect(doc.importSnapshot(snapshot), isTrue);
      await tester.pumpAndSettle();
      expect(builds, 2);
      expect(find.text('fromSnapshot'), findsOneWidget);
    });

    testWidgets('throws a FlutterError when the handler type is omitted',
        (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(doc, 'a');
      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: MaterialApp(
            home: CrdtHandlerBuilder(
              id: 'a',
              builder: (context, handler) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isFlutterError);
    });
  });

  group('CrdtHandlerBuilder (nested)', () {
    testWidgets('rebuilds when a descendant handler changes', (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate())
        ..registerDefaultFactories();
      final root = CRDTMapRefHandler(doc, 'root');
      final child = CRDTListHandler<String>(doc, 'child');
      root.setRef('child', child);

      var nestedBuilds = 0;
      var flatBuilds = 0;
      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: MaterialApp(
            home: Column(
              children: [
                CrdtHandlerBuilder<CRDTMapRefHandler>(
                  id: 'root',
                  nested: true,
                  builder: (context, handler) {
                    nestedBuilds++;
                    return const SizedBox.shrink();
                  },
                ),
                CrdtHandlerBuilder<CRDTMapRefHandler>(
                  id: 'root',
                  builder: (context, handler) {
                    flatBuilds++;
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
        ),
      );
      expect(nestedBuilds, 1);
      expect(flatBuilds, 1);

      // A change to the descendant handler.
      child.insert(0, 'v');
      await tester.pumpAndSettle();

      // nested: true rebuilds; the flat one does not (root itself unchanged).
      expect(nestedBuilds, 2);
      expect(flatBuilds, 1);

      // Removing the child bumps root (revision 1 → 2) while dropping the
      // child's revision (1) from the visit: a plain revision sum would
      // stay at 2 and miss this rebuild.
      root.delete('child');
      await tester.pumpAndSettle();
      expect(nestedBuilds, 3);
      expect(flatBuilds, 2);
    });
  });

  group('CrdtHandlerSelector', () {
    testWidgets('rebuilds only when the selected slice changes',
        (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final a = CRDTListHandler<Map<String, dynamic>>(doc, 'a');

      var builds = 0;
      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: MaterialApp(
            home:
                CrdtHandlerSelector<CRDTListHandler<Map<String, dynamic>>, int>(
              id: 'a',
              selector: (context, handler) => handler.value.length,
              builder: (context, count) {
                builds++;
                return Text('$count', textDirection: TextDirection.ltr);
              },
            ),
          ),
        ),
      );
      expect(builds, 1);

      a.insert(0, {'text': 'a'});
      await tester.pumpAndSettle();
      expect(builds, 2);

      a.update(0, {'text': 'b'});
      await tester.pumpAndSettle();
      expect(builds, 2);
    });
  });

  group('CrdtHandlerListener', () {
    testWidgets('fires only on its handler change', (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final a = CRDTListHandler<String>(doc, 'a');
      final b = CRDTListHandler<String>(doc, 'b');

      var fires = 0;
      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: MaterialApp(
            home: CrdtHandlerListener<CRDTListHandler<String>>(
              id: 'a',
              listener: (context, handler) => fires++,
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      expect(fires, 0);

      a.insert(0, 'x');
      await tester.pumpAndSettle();
      expect(fires, 1);

      b.insert(0, 'y');
      await tester.pumpAndSettle();
      expect(fires, 1);
    });
  });
}
