import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrdtProvider', () {
    testWidgets('value mode exposes the document via CrdtProvider.of',
        (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      late CRDTDocument resolved;

      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: Builder(
            builder: (context) {
              resolved = CrdtProvider.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(identical(resolved, doc), isTrue);
    });

    testWidgets('context.crdtDocument / context.read resolve the document',
        (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      late CRDTDocument viaExtension;
      late CRDTDocument viaRead;

      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: Builder(
            builder: (context) {
              viaExtension = context.crdtDocument;
              viaRead = context.read<CRDTDocument>();
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(identical(viaExtension, doc), isTrue);
      expect(identical(viaRead, doc), isTrue);
    });

    testWidgets('value mode never disposes the caller-owned document',
        (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      await tester.pumpWidget(
        CrdtProvider.value(value: doc, child: const SizedBox.shrink()),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(doc.isDisposed, isFalse);
    });

    testWidgets('context.select rebuilds only when the slice changes',
        (tester) async {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final list = CRDTListHandler<Map<String, dynamic>>(doc, 'list');

      var builds = 0;
      await tester.pumpWidget(
        CrdtProvider.value(
          value: doc,
          child: Builder(
            builder: (context) {
              final count =
                  context.select<CRDTDocument, int>((_) => list.value.length);
              builds++;
              return Text('$count', textDirection: TextDirection.ltr);
            },
          ),
        ),
      );
      expect(builds, 1);

      list.insert(0, {'text': 'a'});
      await tester.pumpAndSettle();
      expect(builds, 2);
      expect(find.text('1'), findsOneWidget);

      // Update in place (length unchanged) -> no rebuild.
      list.update(0, {'text': 'b'});
      await tester.pumpAndSettle();
      expect(builds, 2);
    });

    group('create (owning mode)', () {
      testWidgets('creates the document and exposes it', (tester) async {
        var creations = 0;
        late CRDTDocument resolved;

        await tester.pumpWidget(
          CrdtProvider(
            create: (_) {
              creations++;
              return CRDTDocument(peerId: PeerId.generate());
            },
            lazy: false,
            child: Builder(
              builder: (context) {
                resolved = CrdtProvider.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(creations, 1);
        expect(resolved.isDisposed, isFalse);
      });

      testWidgets('disposes the created document when removed', (tester) async {
        late CRDTDocument created;

        await tester.pumpWidget(
          CrdtProvider(
            create: (_) => created = CRDTDocument(peerId: PeerId.generate()),
            lazy: false,
            child: const SizedBox.shrink(),
          ),
        );
        expect(created.isDisposed, isFalse);

        await tester.pumpWidget(const SizedBox.shrink());
        expect(created.isDisposed, isTrue);
      });
    });
  });
}
