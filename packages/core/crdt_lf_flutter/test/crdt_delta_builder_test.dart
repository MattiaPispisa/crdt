import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrdtHandlerDeltaBuilder', () {
    late CRDTDocument doc;

    setUp(() {
      doc = CRDTDocument(peerId: PeerId.generate());
    });

    /// A host that renders the value the builder is handed, and counts how
    /// often it is asked for it.
    Widget host({
      required List<List<String>> seen,
      String id = 'todos',
    }) {
      return CrdtProvider.value(
        value: doc,
        child: MaterialApp(
          home: CrdtHandlerDeltaBuilder<List<String>, SequenceDelta<String>>(
            id: id,
            builder: (context, todos) {
              seen.add(todos);
              return Text(todos.join(','));
            },
          ),
        ),
      );
    }

    testWidgets('the first frame already shows the value', (tester) async {
      final list = CRDTListHandler<String>(doc, 'todos')..insert(0, 'a');
      final seen = <List<String>>[];

      await tester.pumpWidget(host(seen: seen));

      // Before any event is delivered: the read happens while attaching, so
      // there is no empty frame to see.
      expect(seen.single, ['a']);
      expect(find.text('a'), findsOneWidget);
      expect(list.value, ['a']);
    });

    testWidgets('moves the value with each change, local and remote',
        (tester) async {
      final list = CRDTListHandler<String>(doc, 'todos')..insert(0, 'a');
      final seen = <List<String>>[];
      await tester.pumpWidget(host(seen: seen));

      list.insert(1, 'b');
      await tester.pumpAndSettle();
      expect(seen.last, ['a', 'b']);

      final remote = CRDTDocument(peerId: PeerId.generate());
      final remoteList = CRDTListHandler<String>(remote, 'todos');
      remote.importChanges(doc.exportChanges());
      remoteList.insert(2, 'c');
      doc.importChanges(
        remote.exportChanges(fromVersionVector: doc.getVersionVector()),
      );
      await tester.pumpAndSettle();
      expect(seen.last, ['a', 'b', 'c']);

      // The seed, then one rebuild per change — and no read of the handler in
      // between: each value came from the delta before it. It also pins the
      // ownership rule: the handler folds a change into its cached list in
      // place, so a shared list would hold the change before the delta
      // describing it arrives, and the builder would apply it twice.
      expect(seen.length, 3);
    });

    testWidgets('a snapshot import makes it read the value again',
        (tester) async {
      final list = CRDTListHandler<String>(doc, 'todos')..insert(0, 'a');
      final seen = <List<String>>[];
      await tester.pumpWidget(host(seen: seen));

      final other = CRDTDocument(peerId: PeerId.generate());
      CRDTListHandler<String>(other, 'todos')
        ..insert(0, 'x')
        ..insert(1, 'y');
      doc.importSnapshot(other.takeSnapshot());
      await tester.pumpAndSettle();

      // The base the deltas described was replaced. No delta can say what that
      // did, so the builder reads again — and lands on whatever the handler
      // now holds.
      expect(seen.last, list.value);
      expect(seen.last, hasLength(3));
    });

    testWidgets('follows the handler when the id changes', (tester) async {
      CRDTListHandler<String>(doc, 'todos').insert(0, 'a');
      CRDTListHandler<String>(doc, 'other').insert(0, 'z');
      final seen = <List<String>>[];

      await tester.pumpWidget(host(seen: seen));
      expect(seen.last, ['a']);

      await tester.pumpWidget(host(seen: seen, id: 'other'));
      expect(seen.last, ['z']);
    });

    testWidgets('a mismatched delta shape fails with a readable error',
        (tester) async {
      CRDTTextHandler(doc, 'todos').insert(0, 'a');
      await tester.pumpWidget(host(seen: <List<String>>[]));

      final error = tester.takeException();
      expect(error, isA<FlutterError>());
      expect(
        error.toString(),
        contains('CrdtHandlerDeltaBuilder'),
      );
    });

    testWidgets('a text handler drives a String projection', (tester) async {
      final text = CRDTFugueTextHandler(doc, 'note')..insert(0, 'hi');

      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: MaterialApp(
            home: CrdtHandlerDeltaBuilder<String, SequenceDelta<String>>(
              id: 'note',
              builder: (context, value) => Text(value),
            ),
          ),
        ),
      );
      expect(find.text('hi'), findsOneWidget);

      // The same delta shape as the list, moved by a different method — the
      // handler is the one that knows which.
      text.insert(2, '!');
      await tester.pumpAndSettle();
      expect(find.text('hi!'), findsOneWidget);
    });

    testWidgets('a change that moves nothing does not rebuild', (tester) async {
      final list = CRDTListHandler<String>(doc, 'todos')..insert(0, 'a');
      final seen = <List<String>>[];
      await tester.pumpWidget(host(seen: seen));
      expect(seen, hasLength(1));

      // The handler still publishes an event: the change happened, it simply
      // moved nothing. There is no new value to put on screen.
      list.delete(99, 1);
      await tester.pumpAndSettle();

      expect(seen, hasLength(1));
      expect(find.text('a'), findsOneWidget);
    });
  });
}
