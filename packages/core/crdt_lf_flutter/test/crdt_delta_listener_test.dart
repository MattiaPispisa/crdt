import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrdtHandlerDeltaListener', () {
    late CRDTDocument doc;

    setUp(() {
      doc = CRDTDocument(peerId: PeerId.generate());
    });

    /// A host that keeps a projection built only from resets and deltas.
    Widget host({
      required List<String> projection,
      required List<ResetCause> resets,
      required VoidCallback onBuild,
      String id = 'todos',
    }) {
      return CrdtProvider.value(
        value: doc,
        child: MaterialApp(
          home: CrdtHandlerDeltaListener<List<String>, SequenceDelta<String>>(
            id: id,
            onReset: (context, sync, cause) {
              resets.add(cause);
              projection
                ..clear()
                ..addAll(sync.value);
            },
            onDelta: (context, event) {
              final next = event.delta.apply(projection);
              projection
                ..clear()
                ..addAll(next);
            },
            child: Builder(
              builder: (context) {
                onBuild();
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    }

    testWidgets('seeds from an initial reset, then follows the deltas',
        (tester) async {
      final list = CRDTListHandler<String>(doc, 'todos')..insert(0, 'seed');

      final projection = <String>[];
      final resets = <ResetCause>[];
      var builds = 0;
      await tester.pumpWidget(
        host(projection: projection, resets: resets, onBuild: () => builds++),
      );
      await tester.pumpAndSettle();

      expect(resets, [ResetCause.initial]);
      expect(projection, ['seed']);

      list
        ..insert(1, 'a')
        ..insert(2, 'b')
        ..delete(0, 1)
        ..update(0, 'A');
      await tester.pumpAndSettle();

      expect(list.value, ['A', 'b']);
      expect(projection, list.value);
      // Only the initial reset: every change after it arrived as a delta.
      expect(resets, [ResetCause.initial]);
      // The subtree never rebuilt.
      expect(builds, 1);
    });

    testWidgets('follows a remote change too', (tester) async {
      CRDTListHandler<String>(doc, 'todos').insert(0, 'seed');

      final remote = CRDTDocument(peerId: PeerId.generate());
      final remoteList = CRDTListHandler<String>(remote, 'todos');
      remote.importChanges(doc.exportChanges());

      final projection = <String>[];
      final resets = <ResetCause>[];
      await tester.pumpWidget(
        host(projection: projection, resets: resets, onBuild: () {}),
      );
      await tester.pumpAndSettle();

      remoteList.insert(1, 'from-remote');
      doc.importChanges(
        remote.exportChanges(fromVersionVector: doc.getVersionVector()),
      );
      await tester.pumpAndSettle();

      expect(projection, ['seed', 'from-remote']);
      expect(resets, [ResetCause.initial]);
    });

    testWidgets('a snapshot import asks for the value again', (tester) async {
      CRDTListHandler<String>(doc, 'todos').insert(0, 'seed');

      final projection = <String>[];
      final resets = <ResetCause>[];
      await tester.pumpWidget(
        host(projection: projection, resets: resets, onBuild: () {}),
      );
      await tester.pumpAndSettle();

      doc.importSnapshot(doc.takeSnapshot());
      await tester.pumpAndSettle();

      expect(resets, [ResetCause.initial, ResetCause.snapshotImport]);
      expect(projection, ['seed']);
    });

    testWidgets('the deltas a reset already covers are not replayed',
        (tester) async {
      final list = CRDTListHandler<String>(doc, 'todos')..insert(0, 'seed');

      final projection = <String>[];
      final resets = <ResetCause>[];
      await tester.pumpWidget(
        host(projection: projection, resets: resets, onBuild: () {}),
      );
      await tester.pumpAndSettle();

      // Drop the cache and edit in the same turn: the reset and the delta are
      // queued together, and the read the reset triggers already holds the
      // edit. Applying the delta on top would double it.
      list
        ..invalidateCache()
        ..insert(1, 'x');
      await tester.pumpAndSettle();

      expect(list.value, ['seed', 'x']);
      expect(projection, list.value);
    });

    testWidgets('follows the handler when the id changes', (tester) async {
      CRDTListHandler<String>(doc, 'todos').insert(0, 'first');
      final other = CRDTListHandler<String>(doc, 'other')..insert(0, 'second');

      final projection = <String>[];
      final resets = <ResetCause>[];
      await tester.pumpWidget(
        host(projection: projection, resets: resets, onBuild: () {}),
      );
      await tester.pumpAndSettle();
      expect(projection, ['first']);

      await tester.pumpWidget(
        host(
          projection: projection,
          resets: resets,
          onBuild: () {},
          id: 'other',
        ),
      );
      await tester.pumpAndSettle();

      // Seeded again from the handler it now points at, and following it.
      expect(projection, ['second']);
      other.insert(1, 'third');
      await tester.pumpAndSettle();
      expect(projection, other.value);
    });

    testWidgets('a mismatched delta shape fails with a readable error',
        (tester) async {
      CRDTMapHandler<String>(doc, 'todos').set('k', 'v');

      final projection = <String>[];
      final resets = <ResetCause>[];
      await tester.pumpWidget(
        host(projection: projection, resets: resets, onBuild: () {}),
      );

      expect(
        tester.takeException(),
        isA<FlutterError>().having(
          (e) => e.message,
          'message',
          contains('to publish deltas of that shape'),
        ),
      );
    });

    testWidgets('a text handler drives a String projection', (tester) async {
      final note = CRDTFugueTextHandler(doc, 'note')..insert(0, 'hello');

      var projection = '';
      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: MaterialApp(
            home: CrdtHandlerDeltaListener<String, SequenceDelta<String>>(
              id: 'note',
              onReset: (context, sync, cause) => projection = sync.value,
              onDelta: (context, event) =>
                  projection = event.delta.applyToText(projection),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(projection, 'hello');

      note
        ..insert(5, ' world')
        ..delete(0, 1)
        ..update(0, 'H');
      await tester.pumpAndSettle();

      expect(note.value, 'Hllo world');
      expect(projection, note.value);
    });
  });
}
