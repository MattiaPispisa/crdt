import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../helpers/pn_counter_handler.dart';

/// A document holding one text handler and one counter, with a change for
/// each, and no snapshot.
CRDTDocument _documentWithChanges() {
  final doc = CRDTDocument(peerId: PeerId.generate());
  CRDTFugueTextHandler(doc, 'text').insert(0, 'hi');
  PNCounterHandler(doc, 'counter').increment(2);
  return doc;
}

void main() {
  group('CRDTDocument.describeDataRequirements', () {
    test('reads the kinds from the changes, with no handler registered', () {
      final source = _documentWithChanges();

      // A bare document, the way a relaying server holds one: it has the
      // changes and nothing else. This is the case the description exists for.
      final server = CRDTDocument(peerId: PeerId.generate())
        ..importChanges(source.exportChanges());
      expect(server.registeredHandlers, isEmpty);

      final capabilities = server.describeDataRequirements();

      expect(
        capabilities['CRDTFugueTextHandler']?.operationKinds,
        contains(OperationType.kindInsert),
      );
      expect(
        capabilities['PNCounterHandler']?.operationKinds,
        {PNCounterHandler.incrementKind},
      );
      // A change envelope says nothing about snapshots.
      expect(capabilities['PNCounterHandler']?.blobVersions, isNull);
    });

    test('picks up the changes that arrive after the first call', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final text = CRDTFugueTextHandler(doc, 'text')..insert(0, 'hi');

      expect(doc.describeDataRequirements()['PNCounterHandler'], isNull);

      PNCounterHandler(doc, 'counter').increment();
      text.insert(0, 'x');

      expect(
        doc.describeDataRequirements()['PNCounterHandler']?.operationKinds,
        {PNCounterHandler.incrementKind},
      );
    });

    test('folds a change as it is applied, not by walking the log again', () {
      // Where the fold happens is the point: a version vector is a causal
      // cursor, not a scan cursor. Folding at the one place every change
      // passes means the answer holds even once the log no longer has it.
      final source = _documentWithChanges();

      final doc = CRDTDocument(peerId: PeerId.generate())
        ..describeDataRequirements()
        ..importChanges(source.exportChanges())
        ..takeSnapshot();

      expect(doc.exportChanges(), isEmpty);
      expect(
        doc.describeDataRequirements()['PNCounterHandler']?.operationKinds,
        {PNCounterHandler.incrementKind},
      );
    });

    test('a prune takes nothing away from what was already read', () {
      final doc = _documentWithChanges();

      final before = doc.describeDataRequirements();
      doc.takeSnapshot();
      expect(doc.exportChanges(), isEmpty);

      // The fold is kept, so pruning cannot make a document look like it needs
      // less than it did a moment earlier.
      final after = doc.describeDataRequirements();
      for (final type in before.handlerTypes) {
        expect(
          after[type]?.operationKinds,
          before[type]?.operationKinds,
          reason: type,
        );
      }
    });

    test('survives a snapshot round-trip onto a bare document', () {
      // The case the whole guard exists for: a server compacts, restarts, and
      // reloads from the snapshot alone. Without the record the snapshot
      // carries it would report nothing and accept every client.
      final pruned = _documentWithChanges();
      final before = pruned.describeDataRequirements();

      final reloaded = CRDTDocument(peerId: PeerId.generate())
        ..importSnapshot(pruned.takeSnapshot());

      expect(reloaded.registeredHandlers, isEmpty);
      final after = reloaded.describeDataRequirements();

      expect(
        after['PNCounterHandler']?.operationKinds,
        before['PNCounterHandler']?.operationKinds,
      );
      expect(
        after['CRDTFugueTextHandler']?.operationKinds,
        before['CRDTFugueTextHandler']?.operationKinds,
      );
    });

    test('records the blob version of every type it snapshotted', () {
      final doc = _documentWithChanges();
      final written = doc
          .describeBuildCapabilities()['CRDTFugueTextHandler']!
          .blobVersions;

      final reloaded = CRDTDocument(peerId: PeerId.generate())
        ..importSnapshot(doc.takeSnapshot());

      expect(
        reloaded.describeDataRequirements()['CRDTFugueTextHandler']
            ?.blobVersions,
        written,
      );
    });

    test('carries the record forward when it snapshots again', () {
      // A build that cannot read a type still has to pass on that the data
      // needs it, or the guard fades away one compaction at a time.
      final pruned = _documentWithChanges()..takeSnapshot();

      final relay = CRDTDocument(peerId: PeerId.generate())
        ..importSnapshot(pruned.takeSnapshot());
      final second = relay.takeSnapshot();

      final reloaded = CRDTDocument(peerId: PeerId.generate())
        ..importSnapshot(second);

      expect(
        reloaded.describeDataRequirements()['PNCounterHandler']?.operationKinds,
        {PNCounterHandler.incrementKind},
      );
    });

    test('merging two snapshots keeps what both sides needed', () async {
      // A store-and-forward server with no handler open, merging what two
      // peers sent it. What a persistence adapter writes down is the snapshot
      // the merge publishes — so that is what has to carry both records. If
      // the merge keeps one side only, the server reads back less than it
      // holds and lets in a peer that cannot read the rest.
      final peerA = CRDTDocument(peerId: PeerId.generate());
      CRDTFugueTextHandler(peerA, 'text').insert(0, 'hi');
      final peerB = CRDTDocument(peerId: PeerId.generate());
      PNCounterHandler(peerB, 'counter').increment(2);

      final server = CRDTDocument(peerId: PeerId.generate());
      final persisted = <Snapshot>[];
      final sub = server.events.listen((e) {
        if (e is DocumentSnapshotUpdated) {
          persisted.add(e.snapshot);
        }
      });
      addTearDown(sub.cancel);

      server
        ..mergeSnapshot(peerA.takeSnapshot())
        ..mergeSnapshot(peerB.takeSnapshot());
      await Future<void>.delayed(Duration.zero);

      final restarted = CRDTDocument(peerId: PeerId.generate())
        ..importSnapshot(Snapshot.fromBytes(persisted.last.toBytes()));

      final capabilities = restarted.describeDataRequirements();
      expect(capabilities.handlerTypes, contains('CRDTFugueTextHandler'));
      expect(capabilities.handlerTypes, contains('PNCounterHandler'));
    });

    test('widens the range to cover two builds that disagree', () {
      // The record from a peer on another build reaches a document through a
      // merge. Folding it down to one number would say the document needs one
      // version when it holds two, and a peer that reads the other one would
      // be let in and then fail on the blob.
      final doc = _documentWithChanges()..takeSnapshot();

      final fromOlderPeer = DocumentRequirements({
        'CRDTFugueTextHandler': const HandlerFormats(
          operationKinds: {0},
          blobVersions: BlobVersionRange.single(99),
        ),
      });
      final merged = doc.describeDataRequirements().merge(fromOlderPeer);

      // Widened to cover both ends. A range says more than the two layouts
      // actually present, and that is the trade: a peer is refused when it
      // cannot reach an endpoint, never because of a gap in the middle.
      expect(
        merged['CRDTFugueTextHandler']!.blobVersions,
        const BlobVersionRange(1, 99),
      );
    });

    test('a snapshot replaces the blob versions instead of adding to them', () {
      // A snapshot rewrites the blob of every handler it holds, so a version
      // merged in from a peer on another build is no longer in the data. Left
      // in the record it would refuse a peer over something this document no
      // longer serves. Kinds are the other way round: a change is immutable.
      final doc = _documentWithChanges()..takeSnapshot();
      final foreign = DocumentRequirements({
        'CRDTFugueTextHandler': const HandlerFormats(
          operationKinds: {0},
          blobVersions: BlobVersionRange.single(99),
        ),
      });
      expect(
        doc.describeDataRequirements().merge(foreign)['CRDTFugueTextHandler']!
            .blobVersions,
        const BlobVersionRange(1, 99),
      );

      doc.takeSnapshot();

      expect(
        doc.describeDataRequirements()['CRDTFugueTextHandler']!.blobVersions,
        const BlobVersionRange.single(1),
      );
    });

    test('records a type it knows only by the blob version it holds', () {
      // A document restored from a snapshot written before the record existed
      // has no kinds at all. Writing a record that says it needs nothing, while
      // holding a blob whose version it knows, is the silent gap this closes.
      final seeded = _documentWithChanges();
      final full = seeded.takeSnapshot();
      final legacy = Snapshot.create(
        versionVector: full.versionVector,
        data: {'text': full.data['text']!},
      );

      final server = CRDTDocument(peerId: PeerId.generate())
        ..importSnapshot(legacy);
      CRDTFugueTextHandler(server, 'text');
      expect(server.exportChanges(), isEmpty);

      final reloaded = CRDTDocument(peerId: PeerId.generate())
        ..importSnapshot(server.takeSnapshot());

      final capability =
          reloaded.describeDataRequirements()['CRDTFugueTextHandler'];
      expect(capability, isNotNull);
      expect(capability!.blobVersions, const BlobVersionRange.single(1));
    });

    test('reads the kind of a stamped operation without its flag', () {
      // The kind travels in one byte with the stamped bit on top. Reading the
      // framing by hand has to strip it exactly as the codec does, or a
      // stamped kind is recorded as a kind nobody has.
      final doc = CRDTDocument(peerId: PeerId.generate());
      // A movable list stamps update and move.
      CRDTFugueMovableListHandler<String>(doc, 'list')
        ..insert(0, 'a')
        ..insert(1, 'b')
        ..move(0, 1);

      final kinds = doc
          .describeDataRequirements()['CRDTFugueMovableListHandler<String>']!
          .operationKinds;

      expect(kinds, contains(OperationType.kindMove));
      expect(kinds.every((k) => k <= OperationType.maxKind), isTrue);
      // Cross-check against the codec, which is the definition of the value.
      final fromCodec = doc
          .exportChanges()
          .map((c) => OperationEnvelopeCodec.decode(c.payloadBytes()).kind)
          .toSet();
      expect(kinds, fromCodec);
    });

    test('folds every change whatever order it arrives in', () {
      // The reason the fold sits on the apply path: a watermark over the store
      // would miss a change that lands out of order.
      final author = CRDTDocument(peerId: PeerId.generate());
      CRDTFugueTextHandler(author, 'text').insert(0, 'hi');
      PNCounterHandler(author, 'counter').increment(2);
      final changes = author.exportChanges().reversed.toList();

      final target = CRDTDocument(peerId: PeerId.generate())
        ..importChanges(changes);

      final capabilities = target.describeDataRequirements();
      expect(capabilities.handlerTypes, contains('CRDTFugueTextHandler'));
      expect(capabilities.handlerTypes, contains('PNCounterHandler'));
    });

    test('is read-only: the maps it hands out cannot be edited', () {
      final doc = _documentWithChanges();
      final capabilities = doc.describeDataRequirements();

      expect(capabilities.byHandlerType.clear, throwsUnsupportedError);
      expect(
        () => capabilities['PNCounterHandler']!.operationKinds.add(9),
        throwsUnsupportedError,
      );
    });
  });
}
