import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../conformance/handler_conformance.dart';

void main() {
  // Non-BMP tokens, so every clause also walks text outside the BMP.
  runHandlerConformanceTests(
    spec: CRDTFugueTextHandler.spec,
    read: (text) => text.value,
    edit: (text, random, token) {
      final length = text.length;
      switch (length == 0 ? 0 : random.nextInt(3)) {
        case 0:
          text.insert(random.nextInt(length + 1), '\u{1F600}$token');
        case 1:
          text.delete(random.nextInt(length), random.nextInt(3) + 1);
        case _:
          text.update(random.nextInt(length), '\u{1F389}$token');
      }
    },
  );

  group('CRDTFugueTextHandler', () {
    test('exposes a stable handlerType (minification-safe factory key)', () {
      final handler = CRDTFugueTextHandler(CRDTDocument(), 'text1');
      expect(handler.handlerType, 'CRDTFugueTextHandler');
    });

    test('should insert text', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1')..insert(0, 'Hello');
      expect(handler.value, 'Hello');
      handler.insert(5, ' World');
      expect(handler.value, 'Hello World');
    });

    test('should respect the order of a backward insertion sequence', () {
      final doc = CRDTDocument();
      // Repeated inserts at the same index put each fragment ahead of the
      // previous one, so the fragments read in reverse insertion order.
      final handler = CRDTFugueTextHandler(doc, 'text1')
        ..insert(0, 'XYZ')
        ..insert(2, 'A');
      expect(handler.value, 'XYAZ');

      handler.insert(2, 'B');
      expect(handler.value, 'XYBAZ');

      handler.insert(2, 'C');
      expect(handler.value, 'XYCBAZ');
    });

    test('should handle empty text insertion', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1')..insert(0, '');
      expect(handler.value, '');
      expect(handler.length, 0);
    });

    test('should delete text', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1')
        ..insert(0, 'Hello World');
      expect(handler.value, 'Hello World');

      handler.delete(5, 6); // Delete " World"
      expect(handler.value, 'Hello');

      handler.delete(0, 2); // Delete from the start
      expect(handler.value, 'llo');
    });

    test(
      'should update text',
      () {
        final doc = CRDTDocument();
        final handler = CRDTFugueTextHandler(doc, 'text1')
          ..insert(0, 'Hello World');
        expect(handler.value, 'Hello World');

        handler.update(5, 'Beautiful');
        expect(handler.value, 'HelloBeauti');
      },
    );

    group('update overwrites the element in place', () {
      /// A second document sharing [doc]'s history, so merges are
      /// deterministic.
      CRDTDocument peerOf(CRDTDocument doc) {
        final remote = CRDTDocument(peerId: PeerId.generate());
        CRDTFugueTextHandler(remote, 'text');
        remote.importChanges(doc.exportChanges());
        return remote;
      }

      CRDTFugueTextHandler textOf(CRDTDocument doc) =>
          doc.registeredHandlers['text']! as CRDTFugueTextHandler;

      // Two updates used to make two elements out of one. Now the losing
      // value is simply dropped, and both peers drop the same one.
      test('two peers updating the same element converge on one value', () {
        final a = CRDTDocument(peerId: PeerId.generate());
        final textA = CRDTFugueTextHandler(a, 'text')..insert(0, 'abc');
        final b = peerOf(a);
        final textB = textOf(b);

        textA.update(1, 'X');
        textB.update(1, 'Y');

        a.importChanges(b.exportChanges());
        b.importChanges(a.exportChanges());

        expect(textA.value, equals(textB.value));
        expect(textA.value, anyOf('aXc', 'aYc'));
        expect(textA.length, equals(3));
      });

      test('an update loses against a concurrent delete, in both orders', () {
        for (final deleteArrivesFirst in [true, false]) {
          final a = CRDTDocument(peerId: PeerId.generate());
          final textA = CRDTFugueTextHandler(a, 'text')..insert(0, 'abc');
          final b = peerOf(a);
          final textB = textOf(b);

          textA.update(1, 'X');
          textB.delete(1, 1);

          if (deleteArrivesFirst) {
            a.importChanges(b.exportChanges());
            b.importChanges(a.exportChanges());
          } else {
            b.importChanges(a.exportChanges());
            a.importChanges(b.exportChanges());
          }

          expect(textA.value, equals(textB.value));
          expect(textA.value, equals('ac'));
        }
      });

      // The reason to pick this handler over `CRDTTextHandler` is that an
      // anchor keeps resolving. An update used to tombstone the anchored
      // element, which broke exactly that.
      test('an anchor survives a remote update of the anchored element', () {
        final doc = CRDTDocument(peerId: PeerId.generate());
        final text = CRDTFugueTextHandler(doc, 'text')..insert(0, 'hello');
        final caret = text.stablePositionAt(3); // after the second "l"

        final remote = peerOf(doc);
        textOf(remote).update(2, 'L');
        doc.importChanges(remote.exportChanges());

        expect(text.value, equals('heLlo'));
        expect(text.indexOfStablePosition(caret), equals(3));
      });

      // The change carrying an operation takes the id minted when the
      // operation was registered, so ids have to be minted for **every**
      // operation and not only for the stamped ones. Mint them only for the
      // stamped ones and this transaction breaks: `insert` would take its id
      // at commit, after `update` had already taken an earlier one, so the
      // update would sort ahead of the insert it depends on, find no node to
      // overwrite, and vanish without a word.
      test('an update sees an insert made earlier in the same transaction', () {
        final doc = CRDTDocument(peerId: PeerId.generate());
        final text = CRDTFugueTextHandler(doc, 'text');

        doc.runInTransaction(() {
          text
            ..insert(0, 'ab')
            ..update(0, 'X');
        });

        expect(text.value, equals('Xb'));

        // And a peer replaying the two changes in sorted order agrees.
        final remote = CRDTDocument(peerId: PeerId.generate());
        final remoteText = CRDTFugueTextHandler(remote, 'text');
        remote.importChanges(doc.exportChanges());
        expect(remoteText.value, equals('Xb'));
      });

      // An update creates no node, so it must not spend a counter either.
      test('an update spends no element counter', () {
        final doc = CRDTDocument(peerId: PeerId.generate());
        final text = CRDTFugueTextHandler(doc, 'text')..insert(0, 'abc');
        expect(text.nodeAt(2).counter, equals(2));

        text
          ..update(0, 'A')
          ..update(1, 'B')
          ..update(2, 'C')
          ..insert(3, 'd');

        expect(text.value, equals('ABCd'));
        expect(text.nodeAt(3).counter, equals(3));
      });
    });

    test('should change text', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1')
        ..insert(0, 'Hello World')
        ..change('Hello Brave New World');
      expect(handler.value, 'Hello Brave New World');
    });

    test('should change text with complex transformations', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1')
        ..insert(0, 'The quick brown fox jumps over the lazy dog')
        ..change('The quick red fox leaped over the lazy cat');
      expect(handler.value, 'The quick red fox leaped over the lazy cat');
    });

    test('should change from empty to text', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1')..change('Hello World');
      expect(handler.value, 'Hello World');
    });

    test('should change from text to empty', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1')
        ..insert(0, 'Hello World')
        ..change('');
      expect(handler.value, '');
    });

    test('should change text within transaction', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1')..insert(0, 'ABC');

      doc.runInTransaction(() {
        handler.change('AXBYCZ');
      });

      expect(handler.value, 'AXBYCZ');
    });

    test('should change text with unicode and emoji', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1')
        ..insert(0, 'Hello 😀 World')
        ..change('Hello 🎉 Beautiful 🌍 World');
      expect(handler.value, 'Hello 🎉 Beautiful 🌍 World');
    });

    test('should change multiline text', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1')
        ..insert(0, 'Line 1\nLine 2\nLine 3')
        ..change('Line 1\nModified Line 2\nLine 3\nLine 4');
      expect(handler.value, 'Line 1\nModified Line 2\nLine 3\nLine 4');
    });

    test('should change text and sync correctly between peers', () {
      final doc1 = CRDTDocument();
      final doc2 = CRDTDocument();
      final handler1 = CRDTFugueTextHandler(doc1, 'text1');
      final handler2 = CRDTFugueTextHandler(doc2, 'text1');

      // Initial state
      handler1.insert(0, 'Hello');
      doc2.importChanges(doc1.exportChanges());
      expect(handler2.value, 'Hello');

      // Use change on doc1
      handler1.change('Hello World');
      doc2.importChanges(doc1.exportChanges());

      expect(handler1.value, 'Hello World');
      expect(handler2.value, 'Hello World');
    });

    test('should handle concurrent changes from different peers', () {
      final doc1 = CRDTDocument();
      final doc2 = CRDTDocument();
      final handler1 = CRDTFugueTextHandler(doc1, 'text1');
      final handler2 = CRDTFugueTextHandler(doc2, 'text1');

      // Initial state
      handler1.insert(0, 'ABC');
      doc2.importChanges(doc1.exportChanges());

      // Concurrent changes
      handler1.change('AXBC'); // doc1: A -> AX
      handler2.change('AYBC'); // doc2: A -> AY

      // Sync
      doc2.importChanges(doc1.exportChanges());
      doc1.importChanges(doc2.exportChanges());

      // Both should converge
      expect(handler1.value, handler2.value);
      expect(handler1.value, contains('X'));
      expect(handler1.value, contains('Y'));
    });

    test('should change preserves Fugue ordering', () {
      final doc1 = CRDTDocument();
      final doc2 = CRDTDocument();
      final handler1 = CRDTFugueTextHandler(doc1, 'text1');
      final handler2 = CRDTFugueTextHandler(doc2, 'text1');

      // Initial: both have "Hello"
      handler1.insert(0, 'Hello');
      doc2.importChanges(doc1.exportChanges());

      // Doc1 changes to "Hello World"
      handler1.change('Hello World');

      // Doc2 concurrently inserts "Beautiful " after "Hello"
      handler2.insert(5, ' Beautiful');

      // Sync
      final changes1 = doc1.exportChanges();
      final changes2 = doc2.exportChanges();
      doc2.importChanges(changes1);
      doc1.importChanges(changes2);

      // Both should converge
      expect(handler1.value, handler2.value);
      // Should contain both modifications
      expect(handler1.value, contains('Beautiful'));
      expect(handler1.value, contains('World'));
    });

    test('should handle multiple operations', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1')
        ..insert(0, 'Hello World')
        ..delete(5, 6)
        ..insert(5, ' Dart!')
        ..update(6, 'World')
        ..insert(11, ' and Flutter!');
      expect(handler.value, 'Hello World and Flutter!');
    });

    test('should handle out of bounds deletion', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1')
        ..insert(0, 'Hello')
        ..delete(10, 5); // Try to delete out of bounds
      expect(handler.value, 'Hello');
    });

    test('should handle value caching', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1')..insert(0, 'Hello');
      final value1 = handler.value;
      final value2 = handler.value;
      expect(identical(value1, value2), isTrue);

      // Modify the text to invalidate cache
      handler.insert(5, ' World');
      final value3 = handler.value;
      expect(identical(value1, value3), isFalse);
    });

    test('should handle value caching on independent handlers', () {
      final doc = CRDTDocument();
      final handler1 = CRDTFugueTextHandler(doc, 'text1');
      final handler2 = CRDTFugueTextHandler(doc, 'text2');

      handler1.insert(0, 'Hello');
      final value1 = handler1.value;

      // Modify through another handler to change document version
      handler2.insert(0, 'World');

      final value2 = handler1.value;
      expect(identical(value1, value2), isTrue);
    });

    test('should maintain correct counter for element IDs', () {
      final doc = CRDTDocument();
      CRDTFugueTextHandler(doc, 'text1')
        // Insert multiple characters
        ..insert(0, 'Hello')
        ..insert(5, ' World')
        ..insert(11, '!');

      // Each character should have a unique ID (decode body from bytes).
      // Insert operation body layout:
      //   leftOrigin (FugueElementID) | rightOrigin (FugueElementID) |
      //   itemsCount (varint) | [item.id (FugueElementID), textLen, text]*
      final changes = doc.exportChanges();
      final ids = <int>[];
      for (final c in changes) {
        final env = OperationEnvelopeCodec.decode(c.payloadBytes());
        final body = c.payloadBytes().sublist(env.bodyOffset);
        var offset = 0;
        final leftRec = FugueElementID.readFromBytes(body, offset: offset);
        offset = leftRec.nextOffset;
        final rightRec = FugueElementID.readFromBytes(body, offset: offset);
        offset = rightRec.nextOffset;
        final countRec = UVarint.read(body, offset: offset);
        offset = countRec.nextOffset;
        for (var i = 0; i < countRec.value; i += 1) {
          final idRec = FugueElementID.readFromBytes(body, offset: offset);
          offset = idRec.nextOffset;
          ids.add(idRec.value.counter!);
          final textLenRec = UVarint.read(body, offset: offset);
          offset = textLenRec.nextOffset + textLenRec.value;
        }
      }
      expect(ids, equals([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]));
    });

    test('toString returns correct string representation', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1')
        ..insert(0, 'Hello World');
      expect(handler.toString(), equals('CRDTFugueText(text1, "Hello World")'));
    });

    test('toString truncates long text', () {
      final doc = CRDTDocument();
      final handler = CRDTFugueTextHandler(doc, 'text1')
        ..insert(0, 'This is a very long text that should be truncated');
      expect(
        handler.toString(),
        equals('CRDTFugueText(text1, "This is a very long ...")'),
      );
    });

    test('should handle concurrent insertions without interleaving', () {
      // Create two documents with their own handlers
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final handler1 = CRDTFugueTextHandler(doc1, 'text1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final handler2 = CRDTFugueTextHandler(doc2, 'text1');

      // Initial state
      handler1.insert(0, 'Hello');

      // Sync doc1 to doc2
      final changes1 = doc1.exportChanges();
      doc2.importChanges(changes1);

      expect(handler1.value, 'Hello');
      expect(handler2.value, 'Hello');

      // Concurrent edits
      handler1.insert(5, ' World'); // doc1: "Hello World"
      handler2.insert(5, ' Dart'); // doc2: "Hello Dart"

      // Sync both ways
      final changes1After = doc1.exportChanges();
      final changes2After = doc2.exportChanges();

      doc2.importChanges(changes1After);
      doc1.importChanges(changes2After);

      // Both should have the same final state
      expect(handler1.value, handler2.value);

      // Check that the insertions are not interleaved
      final finalText = handler1.value;
      expect(finalText.contains(' World'), isTrue);
      expect(finalText.contains(' Dart'), isTrue);

      handler1.insert(0, 'Z');
      expect(handler1.value, 'ZHello World Dart');
      doc2.importChanges(doc1.exportChanges());
      expect(handler2.value, 'ZHello World Dart');
    });

    test('should handle complex concurrent edits without interleaving', () {
      // Create three documents with their own handlers
      final doc1 = CRDTDocument(
        peerId: PeerId.parse('5cff68c5-0b34-4d9d-bd43-359db69f8fb6'),
      );
      final handler1 = CRDTFugueTextHandler(doc1, 'text1');

      final doc2 = CRDTDocument(
        peerId: PeerId.parse('41131068-f7f9-4938-b2f5-5f44320d8b3d'),
      );
      final handler2 = CRDTFugueTextHandler(doc2, 'text1');

      final doc3 = CRDTDocument(
        peerId: PeerId.parse('4f7db8d4-9306-49e1-a297-d0c14030a14a'),
      );
      final handler3 = CRDTFugueTextHandler(doc3, 'text1');

      // Initial state
      handler1.insert(0, 'Shared Text');

      // Sync doc1 to doc2 and doc3
      final changes1 = doc1.exportChanges();
      doc2.importChanges(changes1);
      doc3.importChanges(changes1);

      expect(handler1.value, 'Shared Text');
      expect(handler2.value, 'Shared Text');
      expect(handler3.value, 'Shared Text');

      // Concurrent edits
      handler1.insert(11, ' - Edited by User1');
      handler2.insert(11, ' - Modified by User2');
      handler3.insert(11, ' - Updated by User3');

      // Sync all documents
      final changes1After = doc1.exportChanges();
      final changes2After = doc2.exportChanges();
      final changes3After = doc3.exportChanges();

      doc2.importChanges(changes1After);
      doc3.importChanges(changes1After);

      doc1.importChanges(changes2After);
      doc3.importChanges(changes2After);

      doc1.importChanges(changes3After);
      doc2.importChanges(changes3After);

      // All should have the same final state
      expect(handler1.value, handler2.value);
      expect(handler2.value, handler3.value);

      // Each user's text stayed contiguous, i.e. the three runs did not
      // interleave.
      final finalText = handler1.value;
      expect(finalText.contains(' - Edited by User1'), true);
      expect(finalText.contains(' - Modified by User2'), true);
      expect(finalText.contains(' - Updated by User3'), true);
    });

    test(
      'complex scenario with 3 peers using concurrent change operations',
      () {
        final peerId1 = PeerId.parse('1427949a-f573-4a07-9a49-c41c4ef4b05e');
        final peerId2 = PeerId.parse('a9a10c7b-bc1d-4410-ad96-744a0a645e45');
        final peerId3 = PeerId.parse('98dd14d4-5392-49a2-b4af-384c8f7383af');

        final doc1 = CRDTDocument(peerId: peerId1);
        final doc2 = CRDTDocument(peerId: peerId2);
        final doc3 = CRDTDocument(peerId: peerId3);

        const handlerId = 'complex-change-text';
        final text1 = CRDTFugueTextHandler(doc1, handlerId);
        final text2 = CRDTFugueTextHandler(doc2, handlerId);
        final text3 = CRDTFugueTextHandler(doc3, handlerId);

        // === Phase 1: Initial state ===
        // All peers start with the same base text
        text1.insert(0, 'Hello World');

        // Sync initial state to all peers
        final initialChanges = doc1.exportChanges();
        doc2.importChanges(initialChanges);
        doc3.importChanges(initialChanges);

        expect(text1.value, 'Hello World');
        expect(text2.value, 'Hello World');
        expect(text3.value, 'Hello World');

        // === Phase 2: Concurrent changes using change() ===
        // Each peer modifies the text differently using change()
        text1.change('Hello Beautiful World'); // Adds "Beautiful"
        text2.change('Hello Amazing World'); // Adds "Amazing"
        text3.change('Hello World!'); // Adds "!"

        // Before sync, each peer has different content
        expect(text1.value, 'Hello Beautiful World');
        expect(text2.value, 'Hello Amazing World');
        expect(text3.value, 'Hello World!');

        // === Phase 3: Partial sync (simulating network delays) ===
        // Only doc1 and doc2 sync initially
        var changes1 = doc1.exportChanges();
        var changes2 = doc2.exportChanges();

        doc1.importChanges(changes2);
        doc2.importChanges(changes1);

        // doc1 and doc2 should converge
        expect(text1.value, equals(text2.value));
        expect(text1.value, contains('Beautiful'));
        expect(text1.value, contains('Amazing'));

        // doc3 is still out of sync
        expect(text3.value, isNot(equals(text1.value)));

        // === Phase 4: Full sync including doc3 ===
        var changes3 = doc3.exportChanges();
        changes1 = doc1.exportChanges();

        doc3.importChanges([...changes1, ...changes2]);
        doc1.importChanges(changes3);
        doc2.importChanges(changes3);

        // All peers should converge
        expect(text1.value, equals(text2.value));
        expect(text2.value, equals(text3.value));
        expect(text1.value, contains('Beautiful'));
        expect(text1.value, contains('Amazing'));
        expect(text1.value, contains('!'));

        final convergedValue = text1.value;

        // === Phase 5: More concurrent changes ===
        // Use change() with more complex transformations
        doc1.runInTransaction(() {
          text1.change('$convergedValue Greetings');
        });

        doc2.runInTransaction(() {
          text2.change('Wow! $convergedValue');
        });

        // doc3 makes a more dramatic change
        text3.change('Completely New Text');

        // === Phase 6: Sync all changes again ===
        changes1 = doc1.exportChanges();
        changes2 = doc2.exportChanges();
        changes3 = doc3.exportChanges();

        doc1.importChanges([...changes2, ...changes3]);
        doc2.importChanges([...changes1, ...changes3]);
        doc3.importChanges([...changes1, ...changes2]);

        // All should converge again
        expect(text1.value, equals(text2.value));
        expect(text2.value, equals(text3.value));

        // All modifications should be present.
        final finalValue = text1.value;
        expect(finalValue, contains('Greetings'));
        expect(finalValue, contains('Wow!'));
        expect(finalValue, contains('mpletely New Text'));
        expect(finalValue, 'CWow! ompletely New Text Greetings');

        // === Phase 7: Snapshot and post-snapshot changes ===
        final snapshot1 = doc1.takeSnapshot();

        // Verify snapshot
        expect(snapshot1.data[handlerId], isNotNull);
        expect(doc2.shouldApplySnapshot(snapshot1), isTrue);
        expect(doc3.shouldApplySnapshot(snapshot1), isTrue);

        doc2.importSnapshot(snapshot1);
        doc3.importSnapshot(snapshot1);

        // All should still be in sync
        expect(text1.value, equals(text2.value));
        expect(text2.value, equals(text3.value));

        // === Phase 8: Post-snapshot concurrent changes ===
        final currentText = text1.value;

        text1.change('$currentText [peer1]');
        text2.change('$currentText [peer2]');
        text3.change('$currentText [peer3]');

        // Final sync
        changes1 = doc1.exportChanges();
        changes2 = doc2.exportChanges();
        changes3 = doc3.exportChanges();

        expect(changes1, isNotEmpty);
        expect(changes2, isNotEmpty);
        expect(changes3, isNotEmpty);

        doc1.importChanges([...changes2, ...changes3]);
        doc2.importChanges([...changes1, ...changes3]);
        doc3.importChanges([...changes1, ...changes2]);

        // Final convergence
        expect(text1.value, equals(text2.value));
        expect(text2.value, equals(text3.value));

        // All peer markers should be present
        final ultimateValue = text1.value;
        expect(ultimateValue, contains('[peer1]'));
        expect(ultimateValue, contains('[peer2]'));
        expect(ultimateValue, contains('[peer3]'));
      },
    );

    group('stablePositionAt / indexOfStablePosition', () {
      late CRDTDocument doc;
      late CRDTFugueTextHandler text;

      setUp(() {
        doc = CRDTDocument(peerId: PeerId.generate());
        text = CRDTFugueTextHandler(doc, 'text');
      });

      /// A peer that shares [doc]'s history, so merges are deterministic.
      CRDTDocument remotePeer() {
        final remote = CRDTDocument(peerId: PeerId.generate());
        CRDTFugueTextHandler(remote, 'text');
        remote.importChanges(doc.exportChanges());
        return remote;
      }

      test('the sequence start is a null id and resolves to 0', () {
        text.insert(0, 'hello');
        expect(text.stablePositionAt(0).isNull, isTrue);
        expect(text.indexOfStablePosition(FugueElementID.nullID()), 0);
        // Empty sequence: any index anchors to the start.
        final empty = CRDTFugueTextHandler(doc, 'empty');
        expect(empty.stablePositionAt(3).isNull, isTrue);
      });

      test('an anchor keeps its place across remote edits before it', () {
        text.insert(0, 'hello world');
        final caret = text.stablePositionAt(5); // after "hello"

        final remote = remotePeer();
        (remote.registeredHandlers['text']! as CRDTFugueTextHandler)
          ..insert(0, 'XXX ')
          ..insert(15, '!!!');
        doc.importChanges(remote.exportChanges());

        expect(text.value, 'XXX hello world!!!');
        expect(text.indexOfStablePosition(caret), 9);
      });

      test('edits after the anchor do not move it', () {
        text.insert(0, 'hello world');
        final caret = text.stablePositionAt(5);
        text
          ..insert(11, '!!!')
          ..delete(6, 5); // "world"
        expect(text.indexOfStablePosition(caret), 5);
      });

      test('a deleted anchor resolves to where the element used to be', () {
        text.insert(0, 'hello');
        final caret = text.stablePositionAt(5); // after the final "o"
        text.delete(2, 3); // "llo" — the anchored element is a tombstone now
        expect(text.value, 'he');
        expect(text.indexOfStablePosition(caret), 2);
      });

      test('an index past the end anchors to the last element', () {
        text.insert(0, 'hi');
        expect(text.stablePositionAt(100), text.stablePositionAt(2));
        expect(text.indexOfStablePosition(text.stablePositionAt(100)), 2);
      });

      test('an unknown element resolves to null (caller falls back)', () {
        text.insert(0, 'hello');
        final foreign = FugueElementID(PeerId.generate(), 42);
        expect(text.indexOfStablePosition(foreign), isNull);
      });

      test('anchors are serializable and resolvable on another peer', () {
        text.insert(0, 'hello world');
        final wire = text.stablePositionAt(5).toBytes();

        final remote = remotePeer();
        final remoteText = remote.registeredHandlers['text']!
            as CRDTFugueTextHandler
          ..insert(0, 'XXX ');

        final caret = FugueElementID.fromBytes(wire);
        expect(remoteText.indexOfStablePosition(caret), 9);
      });
    });

    group('non-BMP round-trip', () {
      test('an emoji is one indivisible element', () {
        final doc = CRDTDocument();
        final text = CRDTFugueTextHandler(doc, 'text')..insert(0, 'a😀b');

        // Three elements, even though the string is four code units long.
        expect(text.length, equals(3));
        expect(text.value.length, equals(4));

        // Deleting the single position the emoji occupies removes all of it.
        text.delete(1, 1);
        expect(text.value, equals('ab'));
      });

      test('a legacy per-code-unit document still reads back correctly', () {
        // Before code-point granularity every UTF-16 code unit was its own
        // element, so an emoji arrived as two lone-surrogate elements. Such a
        // tree keeps projecting the right text; the emoji simply still
        // occupies two positions until it is retyped.
        final doc = CRDTDocument();
        final text = CRDTFugueTextHandler(doc, 'text')
          ..insert(0, 'a')
          ..insert(1, String.fromCharCode(0xD83D))
          ..insert(2, String.fromCharCode(0xDE00))
          ..insert(3, 'b');

        expect(text.value, equals('a😀b'));

        // `length` tracks the index space, not the rune count of the value,
        // so appending at `length` still appends.
        expect(text.length, equals(4));
        text.insert(text.length, '!');
        expect(text.value, equals('a😀b!'));
      });

      test('stable positions round-trip across a non-BMP character', () {
        final doc = CRDTDocument();
        final text = CRDTFugueTextHandler(doc, 'text')..insert(0, 'a😀b');

        for (var i = 0; i <= text.length; i++) {
          expect(
            text.indexOfStablePosition(text.stablePositionAt(i)),
            equals(i),
            reason: 'anchor at rune index $i',
          );
        }
      });

      // Two lone surrogates side by side are two elements that read as one
      // emoji. The snapshot run holds them with no framing of its own, so
      // only the WTF-8 sequence boundaries keep them apart.
      test('two adjacent lone surrogates stay two elements over a snapshot',
          () {
        final high = String.fromCharCode(0xD83D);
        final low = String.fromCharCode(0xDE00);

        final doc = CRDTDocument();
        final text = CRDTFugueTextHandler(doc, 'text')
          ..insert(0, high)
          ..insert(1, low);
        expect(text.length, equals(2));

        final snapBytes = doc.takeSnapshot(pruneHistory: false).toBytes();

        final reloaded = CRDTDocument(
          peerId: doc.peerId,
          documentId: doc.documentId,
        );
        final reloadedText = CRDTFugueTextHandler(reloaded, 'text');
        reloaded.import(snapshot: Snapshot.fromBytes(snapBytes));

        expect(reloadedText.length, equals(2));
        expect(reloadedText.value.codeUnits, equals([0xD83D, 0xDE00]));
        // Deleting the first half leaves the second, which a fused element
        // could not do.
        reloadedText.delete(0, 1);
        expect(reloadedText.value.codeUnits, equals([0xDE00]));
      });

      test(
          'two peers concurrently inserting either side of an emoji never '
          'produce mojibake or an unpaired surrogate', () {
        // Under the old UTF-16 code-unit unit, offset 2 sat between the two
        // surrogate halves of the emoji: inserting there split it. Under
        // runes that offset does not exist; the closest valid positions are
        // rune 1 (just before the emoji) and rune 2 (just after it).
        final peerA = CRDTDocument();
        final textA = CRDTFugueTextHandler(peerA, 'text')..insert(0, 'a😀b');

        final peerB = CRDTDocument(documentId: peerA.documentId);
        final textB = CRDTFugueTextHandler(peerB, 'text');
        peerB.importChanges(peerA.exportChanges());

        textA.insert(1, 'X'); // just before the emoji
        textB.insert(2, 'Y'); // just after the emoji

        peerB.importChanges(peerA.exportChanges());
        peerA.importChanges(peerB.exportChanges());

        expect(textA.value, equals(textB.value));
        expect(textA.value, contains('😀'));
        expect(textA.value, isNot(contains('�')));
      });
    });

    test(
        'a deep tree (many large inserts, e.g. repeated paste) does not '
        'overflow the stack on read or on reload', () {
      // Regression: the Fugue tree in-order traversal used to be recursive, so
      // a long run of consecutive inserts degenerated it into a deep chain and
      // reading `value` (or rebuilding the index on reload) overflowed the
      // call stack — crashing a Flutter web app after enough pasting.
      final doc = CRDTDocument();
      final text = CRDTFugueTextHandler(doc, 'text');
      const block = 'the quick brown fox jumps over the lazy dog\n\n';
      var length = 0;
      for (var i = 0; i < 600; i++) {
        text.insert(length, block);
        length += block.length;
      }

      // Reading the whole value (in-order traversal) must not overflow.
      expect(text.value.length, 600 * block.length);

      // Reloading from a snapshot rebuilds the positional index with the same
      // in-order traversal — must not overflow either.
      final snapshot = doc.takeSnapshot();
      final restored = CRDTDocument();
      final restoredText = CRDTFugueTextHandler(restored, 'text');
      restored.importSnapshot(snapshot);
      expect(restoredText.value, equals(text.value));
    });
    // The decode path is the same code in all nine handlers, so its contract
    // is asserted once, here. Addressing is no longer part of it: the
    // framework checks the envelope belongs to this handler before looking
    // its kind up in [Handler.operationDecoders].
    group('operation decoding', () {
      test('raises on a kind this build cannot decode', () {
        final doc = CRDTDocument();
        final handler = CRDTFugueTextHandler(doc, 'text1');

        final author = PeerId.generate();
        doc.applyChange(
          Change.fromPayloadBytes(
            id: OperationId(author, HybridLogicalClock(l: 100, c: 1)),
            deps: doc.version,
            author: author,
            payloadBytes: OperationEnvelopeCodec.encode(
              handlerType: handler.handlerType,
              handlerId: handler.id,
              kind: 99,
              body: Uint8List(0),
            ),
          ),
        );

        expect(
          () => handler.value,
          throwsA(
            isA<UnknownOperationKindException>()
                .having((e) => e.kind, 'kind', 99)
                .having((e) => e.handlerId, 'handlerId', 'text1')
                .having(
                  (e) => e.handlerType,
                  'handlerType',
                  'CRDTFugueTextHandler',
                ),
          ),
        );
      });

      // `update` is stamped and `insert` is not, so a peer that got that
      // wrong would leave the two sides picking different winners with no
      // error anywhere. The read has to refuse instead.
      test('a stamped kind that arrives without a stamp raises', () {
        final doc = CRDTDocument();
        final handler = CRDTFugueTextHandler(doc, 'text1')..insert(0, 'ab');

        // The body of a one-item update: nodeID, then the new value.
        final body = BytesBuilder(copy: false);
        UVarint.write(1, body);
        body.add(handler.nodeAt(0).toBytes());
        final value = Wtf8.encode('X');
        UVarint.write(value.length, body);
        body.add(value);

        final author = PeerId.generate();
        doc.applyChange(
          Change.fromPayloadBytes(
            id: OperationId(author, HybridLogicalClock(l: 100, c: 1)),
            deps: doc.version,
            author: author,
            payloadBytes: OperationEnvelopeCodec.encode(
              handlerType: handler.handlerType,
              handlerId: handler.id,
              kind: OperationType.kindUpdate,
              body: body.toBytes(),
            ),
          ),
        );

        expect(
          () => handler.value,
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('is not declared stamped by'),
            ),
          ),
        );
      });

      // The other half of the same disagreement: a peer that stamps `insert`
      // sends one, this build does not read it, and the two would resolve
      // concurrent inserts by different rules. Silent, so the read refuses.
      test('an unstamped kind that arrives with a stamp raises', () {
        final doc = CRDTDocument();
        final handler = CRDTFugueTextHandler(doc, 'text1')..insert(0, 'ab');

        // The body of a one-item insert: the two origins it hangs off, then
        // the item id and its value.
        final body = BytesBuilder(copy: false)
          ..add(handler.nodeAt(0).toBytes())
          ..add(FugueElementID.nullID().toBytes());
        UVarint.write(1, body);
        body.add(FugueElementID(PeerId.generate(), 900).toBytes());
        final value = Wtf8.encode('X');
        UVarint.write(value.length, body);
        body.add(value);

        final author = PeerId.generate();
        doc.applyChange(
          Change.fromPayloadBytes(
            id: OperationId(author, HybridLogicalClock(l: 100, c: 1)),
            deps: doc.version,
            author: author,
            payloadBytes: OperationEnvelopeCodec.encode(
              handlerType: handler.handlerType,
              handlerId: handler.id,
              kind: OperationType.kindInsert,
              stamped: true,
              body: body.toBytes(),
            ),
          ),
        );

        expect(
          () => handler.value,
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('is declared stamped by the'),
            ),
          ),
        );
      });

      test('another handler type is declined before the kind is read', () {
        // Order matters here: an unknown kind under a foreign type tag is
        // somebody else's business. Checking the kind first would turn every
        // handler that shares an id into a reader of everyone else's changes.
        final doc = CRDTDocument();
        final handler = CRDTFugueTextHandler(doc, 'text1')..insert(0, 'Hello');

        final author = PeerId.generate();
        doc.applyChange(
          Change.fromPayloadBytes(
            id: OperationId(author, HybridLogicalClock(l: 100, c: 1)),
            deps: {},
            author: author,
            payloadBytes: OperationEnvelopeCodec.encode(
              handlerType: 'CRDTFugueListHandler<String>',
              handlerId: handler.id,
              kind: 99,
              body: Uint8List(0),
            ),
          ),
        );

        expect(handler.value, 'Hello');
      });

      test('an undecodable change makes the handler raise on every read', () {
        final doc = CRDTDocument();
        final handler = CRDTFugueTextHandler(doc, 'text1')..insert(0, 'Hello');

        final author = PeerId.generate();
        doc.applyChange(
          Change.fromPayloadBytes(
            id: OperationId(author, HybridLogicalClock(l: 100, c: 1)),
            deps: {},
            author: author,
            payloadBytes: OperationEnvelopeCodec.encode(
              handlerType: handler.handlerType,
              handlerId: handler.id,
              kind: 99,
              body: Uint8List(0),
            ),
          ),
        );

        // Applying is zero-decode, so nothing failed above. The disagreement
        // surfaces on the read — and it has to keep surfacing: answering with
        // the pre-change text would be the silent divergence this guards.
        expect(
          () => handler.value,
          throwsA(isA<UnknownOperationKindException>()),
        );
        expect(
          () => handler.value,
          throwsA(isA<UnknownOperationKindException>()),
        );
      });
    });

    group('invert', () {
      CRDTDocument doc() => CRDTDocument(
            peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
          );

      test('undoes a delete at the start of the text', () {
        final document = doc();
        final text = CRDTFugueTextHandler(document, 'text')
          ..insert(0, 'abcdef');
        final undo = CRDTUndoManager(document, captureTimeout: Duration.zero)
          ..track(text);

        text.delete(0, 3);
        expect(text.value, 'def');

        undo.undo();
        expect(text.value, 'abcdef');
      });

      test('undoes a delete of the whole text', () {
        final document = doc();
        final text = CRDTFugueTextHandler(document, 'text')
          ..insert(0, 'abcdef');
        final undo = CRDTUndoManager(document, captureTimeout: Duration.zero)
          ..track(text);

        text.delete(0, 6);
        expect(text.value, '');

        undo.undo();
        expect(text.value, 'abcdef');
      });

      test('a whole `change` is one step', () {
        final document = doc();
        final text = CRDTFugueTextHandler(document, 'text')
          ..insert(0, 'Hello World');
        final undo = CRDTUndoManager(document, captureTimeout: Duration.zero)
          ..track(text);

        document.runInTransaction(() => text.change('Hello Brave World'));
        expect(text.value, 'Hello Brave World');

        undo.undo();
        expect(text.value, 'Hello World');

        undo.redo();
        expect(text.value, 'Hello Brave World');
      });

      test('an undo takes back only this peer, and the two converge', () {
        final a = CRDTDocument(
          peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
        );
        final b = CRDTDocument(
          peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
        );
        final textA = CRDTFugueTextHandler(a, 'text')..insert(0, 'base');
        b.importChanges(a.exportChanges());
        final textB = CRDTFugueTextHandler(b, 'text');

        final undo = CRDTUndoManager(a, captureTimeout: Duration.zero)
          ..track(textA);

        textA.insert(4, '-A');
        textB.insert(4, '-B');

        a.importChanges(b.exportChanges());
        b.importChanges(a.exportChanges());
        expect(textA.value, textB.value);
        final merged = textA.value;
        expect(merged, contains('-A'));
        expect(merged, contains('-B'));

        undo.undo();
        b.importChanges(a.exportChanges());

        expect(textA.value, 'base-B');
        expect(textB.value, textA.value);
      });

      test('a restored run comes back as one block', () {
        final a = CRDTDocument(
          peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
        );
        final b = CRDTDocument(
          peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
        );
        final textA = CRDTFugueTextHandler(a, 'text')..insert(0, 'hello');
        b.importChanges(a.exportChanges());
        final textB = CRDTFugueTextHandler(b, 'text');

        final undo = CRDTUndoManager(a, captureTimeout: Duration.zero)
          ..track(textA);

        // A takes the whole word away while B types inside it.
        textA.delete(0, 5);
        textB.insert(2, 'XY');
        a.importChanges(b.exportChanges());
        b.importChanges(a.exportChanges());
        expect(textA.value, 'XY');

        undo.undo();
        b.importChanges(a.exportChanges());

        // The run is put back as one block, anchored past the tombstones, so
        // what B wrote inside it sits in front rather than within. Both peers
        // agree, which is what matters.
        expect(textA.value, 'XYhello');
        expect(textB.value, textA.value);
      });

      test('an undo of a delete survives a concurrent insert', () {
        final a = CRDTDocument(
          peerId: PeerId.parse('37f1ec87-6ea5-430b-a627-a6b92b56a02d'),
        );
        final b = CRDTDocument(
          peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
        );
        final textA = CRDTFugueTextHandler(a, 'text')..insert(0, 'abcdef');
        b.importChanges(a.exportChanges());
        final textB = CRDTFugueTextHandler(b, 'text');

        final undo = CRDTUndoManager(a, captureTimeout: Duration.zero)
          ..track(textA);

        textA.delete(2, 2); // 'cd'
        expect(textA.value, 'abef');

        // B writes at the very front while A's delete is in flight.
        textB.insert(0, 'Z');
        a.importChanges(b.exportChanges());
        expect(textA.value, 'Zabef');

        undo.undo();
        b.importChanges(a.exportChanges());

        expect(textA.value, 'Zabcdef');
        expect(textB.value, textA.value);
      });
    });
  });
}
