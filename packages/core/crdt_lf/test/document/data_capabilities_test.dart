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
  group('CRDTDocument.describeDataCapabilities', () {
    test('reads the kinds from the changes, with no handler registered', () {
      final source = _documentWithChanges();

      // A bare document, the way a relaying server holds one: it has the
      // changes and nothing else. This is the case the description exists for.
      final server = CRDTDocument(peerId: PeerId.generate())
        ..importChanges(source.exportChanges());
      expect(server.registeredHandlers, isEmpty);

      final capabilities = server.describeDataCapabilities();

      expect(
        capabilities['CRDTFugueTextHandler'],
        contains(OperationType.kindInsert),
      );
      expect(
        capabilities['PNCounterHandler'],
        {PNCounterHandler.incrementKind},
      );
    });

    test('picks up the changes that arrive after the first call', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final text = CRDTFugueTextHandler(doc, 'text')..insert(0, 'hi');

      expect(doc.describeDataCapabilities()['PNCounterHandler'], isNull);

      PNCounterHandler(doc, 'counter').increment();
      text.insert(0, 'x');

      // Only the new changes are decoded, but nothing is missed.
      expect(
        doc.describeDataCapabilities()['PNCounterHandler'],
        {PNCounterHandler.incrementKind},
      );
    });

    test('a prune takes nothing away from what was already read', () {
      final doc = _documentWithChanges();

      final before = doc.describeDataCapabilities();
      doc.takeSnapshot();
      expect(doc.exportChanges(), isEmpty);

      // The fold is kept, so pruning cannot make a document look like it needs
      // less than it did a moment earlier.
      final after = doc.describeDataCapabilities();
      expect(after['PNCounterHandler'], before['PNCounterHandler']);
      expect(after['CRDTFugueTextHandler'], before['CRDTFugueTextHandler']);
    });

    test('a document loaded already pruned reports only its changes', () {
      // The stated limit, pinned so nobody reads more into the result than it
      // holds. A snapshot cannot be described: a flat document's snapshot
      // carries no handler manifest, so its blobs cannot be attributed to a
      // type. A server that restarts onto a pruned document knows nothing
      // until new changes arrive.
      final pruned = _documentWithChanges()..takeSnapshot();

      final reloaded = CRDTDocument(peerId: PeerId.generate())
        ..importSnapshot(pruned.takeSnapshot());

      expect(reloaded.describeDataCapabilities(), isEmpty);

      PNCounterHandler(reloaded, 'counter').increment();
      expect(
        reloaded.describeDataCapabilities()['PNCounterHandler'],
        {PNCounterHandler.incrementKind},
      );
    });

    test('is read-only: the maps it hands out cannot be edited', () {
      final doc = _documentWithChanges();
      final capabilities = doc.describeDataCapabilities();

      expect(capabilities.clear, throwsUnsupportedError);
      expect(
        () => capabilities['PNCounterHandler']!.add(9),
        throwsUnsupportedError,
      );
    });
  });
}
