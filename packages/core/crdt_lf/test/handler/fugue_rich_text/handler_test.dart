// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../conformance/handler_conformance.dart';

List<List<Object?>> _read(CRDTFugueRichTextHandler text) => [
      for (final span in text.value) _s(span.text, span.attributes),
    ];

List<Object?> _s(String text, [Map<String, Object?> attributes = const {}]) =>
    [text, attributes];

void main() {
  runHandlerConformanceTests(
    spec: CRDTFugueRichTextHandler.spec,
    read: _read,
    edit: (text, random, token) {
      final length = text.length;
      switch (length == 0 ? 0 : random.nextInt(5)) {
        case 0:
          final attributes = switch (random.nextInt(3)) {
            0 => const <String, Object?>{},
            1 => {'italic': true},
            _ => {'bold': null, 'size': random.nextInt(4)},
          };
          text.insert(
            random.nextInt(length + 1),
            random.nextInt(4) == 0 ? '\u{1F600}$token\n' : '\u{1F600}$token',
            attributes: attributes,
          );
        case 1:
          text.delete(random.nextInt(length), random.nextInt(3) + 1);
        case 2:
          text.update(random.nextInt(length), '\u{1F389}$token');
        case 3:
          final index = random.nextInt(length);
          final count = random.nextInt(length - index) + 1;
          text.format(
            index,
            count,
            'link',
            token,
            expand: MarkExpand.values[random.nextInt(4)],
          );
        case _:
          final index = random.nextInt(length);
          final count = random.nextInt(length - index) + 1;
          var allBold = true;
          for (var i = index; i < index + count; i++) {
            allBold = allBold && text.attributesAt(i)['bold'] == true;
          }
          text.format(index, count, 'bold', allBold ? null : true);
      }
    },
  );

  final peerA = PeerId.parse('00000000-0000-4000-8000-00000000000a');
  final peerB = PeerId.parse('00000000-0000-4000-8000-00000000000b');
  final peerC = PeerId.parse('00000000-0000-4000-8000-00000000000c');

  CRDTFugueRichTextHandler open(CRDTDocument doc) =>
      doc.handler(CRDTFugueRichTextHandler.spec, 'rich');

  /// A second peer that shares the whole history of [doc].
  CRDTDocument fork(CRDTDocument doc, PeerId peer) =>
      CRDTDocument(peerId: peer)..importChanges(doc.exportChanges());

  void sync(CRDTDocument to, CRDTDocument from) => to.importChanges(
        from.exportChanges(fromVersionVector: to.getVersionVector()),
      );

  group('CRDTFugueRichTextHandler', () {
    test('travels under its own handler type', () {
      expect(open(CRDTDocument()).handlerType, 'CRDTFugueRichTextHandler');
    });

    group('typing at the edges of a span follows expand', () {
      // (expand, typed at the start is marked, typed at the end is marked)
      const table = [
        (MarkExpand.after, false, true),
        (MarkExpand.before, true, false),
        (MarkExpand.both, true, true),
        (MarkExpand.none, false, false),
      ];

      for (final (expand, start, end) in table) {
        test('$expand inside the text', () {
          final text = open(CRDTDocument(peerId: peerA))
            ..insert(0, 'XabY')
            ..format(1, 2, 'k', true, expand: expand)
            ..insert(3, 'e');
          expect(text.attributesAt(3).containsKey('k'), end, reason: 'end');
          text.insert(1, 's');
          expect(text.attributesAt(1).containsKey('k'), start, reason: 'start');
          expect(text.attributesAt(0), isEmpty);
          expect(text.attributesAt(text.length - 1), isEmpty);
        });

        test('$expand over the whole text', () {
          final text = open(CRDTDocument(peerId: peerA))
            ..insert(0, 'ab')
            ..format(0, 2, 'k', true, expand: expand)
            ..insert(2, 'e');
          expect(text.attributesAt(2).containsKey('k'), end, reason: 'end');
          text.insert(0, 's');
          expect(text.attributesAt(0).containsKey('k'), start, reason: 'start');
        });
      }
    });

    test('typing at the end of an unbolded span is not bold', () {
      final text = open(CRDTDocument(peerId: peerA))
        ..insert(0, 'abcd')
        ..format(0, 4, 'bold', true)
        ..format(1, 2, 'bold', null)
        ..insert(3, 'x');
      expect(_read(text), [
        _s('a', {'bold': true}),
        _s('bcx'),
        _s('d', {'bold': true}),
      ]);
    });

    test('unlinking a span also covers the text typed at its edges', () {
      final text = open(CRDTDocument(peerId: peerA))
        ..insert(0, 'abcd')
        ..format(0, 4, 'link', 'u', expand: MarkExpand.none)
        ..format(1, 2, 'link', null, expand: MarkExpand.none)
        ..insert(3, 'y')
        ..insert(1, 'x');
      expect(_read(text), [
        _s('a', {'link': 'u'}),
        _s('xbcy'),
        _s('d', {'link': 'u'}),
      ]);
    });

    test('concurrent bold and unbold converge on the highest stamp', () {
      final a = CRDTDocument(peerId: peerA);
      final textA = open(a)
        ..insert(0, 'abcdef')
        ..format(2, 2, 'bold', true);
      final b = fork(a, peerB);
      final textB = open(b);

      textA.format(0, 4, 'bold', true);
      textB.format(2, 4, 'bold', null);
      final boldWins = a.exportChanges().last.id.compareTo(
                b.exportChanges().last.id,
              ) >
          0;

      final aThenB = fork(a, peerC);
      sync(aThenB, b);
      final bThenA = fork(b, peerC);
      sync(bThenA, a);
      sync(a, b);
      sync(b, a);

      final expected = [
        _s('ab', {'bold': true}),
        if (boldWins) _s('cd', {'bold': true}),
        _s(boldWins ? 'ef' : 'cdef'),
      ];
      for (final doc in [a, b, aThenB, bThenA]) {
        expect(
          _read(open(doc)),
          expected,
          reason: '${doc.peerId}',
        );
      }
    });

    test('a concurrent insert inside a marked range gets the mark', () {
      final a = CRDTDocument(peerId: peerA);
      final textA = open(a)..insert(0, 'abcd');
      final b = fork(a, peerB);
      final textB = open(b);

      textA.format(0, 4, 'bold', true, expand: MarkExpand.none);
      textB.insert(2, 'X');
      sync(a, b);
      sync(b, a);

      for (final text in [textA, textB]) {
        expect(text.text, 'abXcd');
        expect(text.attributesAt(2), {'bold': true});
      }
    });

    test('a mark keeps covering its range after its anchors are deleted', () {
      final text = open(CRDTDocument(peerId: peerA))
        ..insert(0, 'abcde')
        ..format(1, 3, 'bold', true, expand: MarkExpand.none)
        ..delete(3, 1)
        ..delete(1, 1);
      expect(_read(text), [
        _s('a'),
        _s('c', {'bold': true}),
        _s('e'),
      ]);
    });

    test('a mark anchored on an element the tree lacks applies nowhere', () {
      final a = CRDTDocument(peerId: peerA);
      final text = open(a)..insert(0, 'abc');

      // Another document's mark, anchored on its own element.
      final stranger = CRDTDocument(peerId: peerC);
      open(stranger)
        ..insert(0, 'q')
        ..format(0, 1, 'bold', true, expand: MarkExpand.none);
      final mark = stranger.exportChanges().last;
      a.applyChange(
        Change.fromPayloadBytes(
          id: mark.id,
          deps: a.version,
          author: peerC,
          payloadBytes: mark.payloadBytes(),
        ),
      );

      expect(_read(text), [
        _s('abc'),
      ]);
      final restored = CRDTDocument(peerId: peerB)
        ..importSnapshot(a.takeSnapshot());
      expect(open(restored).value.map((s) => s.attributes), [isEmpty]);
    });

    test('a snapshot keeps the anchors: tombstones and expansion survive', () {
      final source = CRDTDocument(peerId: peerA);
      open(source)
        ..insert(0, 'abcdefg')
        ..format(0, 3, 'bold', true)
        ..format(3, 3, 'link', 'u', expand: MarkExpand.none)
        ..delete(2, 1)
        ..delete(4, 1);
      final restored = CRDTDocument(peerId: peerB)
        ..importSnapshot(source.takeSnapshot());
      final text = open(restored);

      expect(_read(text), [
        _s('ab', {'bold': true}),
        _s('de', {'link': 'u'}),
        _s('g'),
      ]);
      text
        ..insert(4, 'y')
        ..insert(2, 'x');
      expect(text.text, 'abxdeyg');
      expect(text.attributesAt(2), {'bold': true});
      expect(text.attributesAt(5), isEmpty);
    });

    group('a redundant mark writes nothing', () {
      test('marking what is already marked, or unmarking what is not', () {
        final doc = CRDTDocument(peerId: peerA);
        final text = open(doc)
          ..insert(0, 'abcd')
          ..format(0, 4, 'bold', true);
        final changes = doc.exportChanges().length;

        text
          ..format(1, 2, 'bold', true)
          ..format(0, 4, 'italic', null)
          ..format(4, 3, 'bold', true);

        expect(doc.exportChanges(), hasLength(changes));
      });

      test('an insert writes only the attributes it does not inherit', () {
        final doc = CRDTDocument(peerId: peerA);
        final text = open(doc)
          ..insert(0, 'ab')
          ..format(0, 2, 'bold', true);
        final changes = doc.exportChanges().length;

        text.insert(1, 'x', attributes: {'bold': true, 'italic': null});
        expect(doc.exportChanges(), hasLength(changes + 1));

        text.insert(1, 'y', attributes: {'bold': null});
        expect(doc.exportChanges(), hasLength(changes + 3));
        expect(text.attributesAt(1), isEmpty);
        expect(text.attributesAt(2), {'bold': true});
      });
    });

    test('every value type crosses the wire and the snapshot', () {
      const values = <String, Object?>{
        'f': false,
        't': true,
        'zero': 0,
        'neg': -42,
        'max': 4503599627370495,
        'min': -4503599627370495,
        'half': 1.5,
        'str': 'h\u{1F600}llo',
      };
      final source = CRDTDocument(peerId: peerA);
      final text = open(source)..insert(0, 'abcdefghij');
      var index = 0;
      for (final MapEntry(:key, :value) in values.entries) {
        text.format(index++, 1, key, value);
      }
      text
        ..format(8, 2, 'gone', 'x')
        ..format(9, 1, 'gone', null);

      final remote = CRDTDocument(peerId: peerB)
        ..importChanges(source.exportChanges());
      final restored = CRDTDocument(peerId: peerC)
        ..importSnapshot(source.takeSnapshot());

      for (final doc in [remote, restored]) {
        final copy = open(doc);
        index = 0;
        for (final MapEntry(:key, :value) in values.entries) {
          final read = copy.attributesAt(index++)[key];
          expect(read, value, reason: key);
          expect(read.runtimeType, value.runtimeType, reason: key);
        }
        expect(copy.attributesAt(8), {'gone': 'x'});
        expect(copy.attributesAt(9), isEmpty);
      }
    });

    test('attributesAt refuses an index outside the text', () {
      final text = open(CRDTDocument())..insert(0, 'ab');
      expect(() => text.attributesAt(-1), throwsRangeError);
      expect(() => text.attributesAt(2), throwsRangeError);
    });

    test('format clamps its range to the text', () {
      final doc = CRDTDocument(peerId: peerA);
      final text = open(doc)..insert(0, '\u{1F600}abc');
      final changes = doc.exportChanges().length;

      text
        ..format(-2, 3, 'bold', true)
        ..format(3, 100, 'italic', true)
        ..format(2, -1, 'size', 1)
        ..format(9, 2, 'size', 1);

      expect(_read(text), [
        _s('\u{1F600}', {'bold': true}),
        _s('ab'),
        _s('c', {'italic': true}),
      ]);
      expect(doc.exportChanges(), hasLength(changes + 2));
    });

    test('change edits only what differs, the formats stay', () {
      final text = open(CRDTDocument(peerId: peerA))
        ..insert(0, 'hello world')
        ..format(0, 5, 'bold', true)
        ..change('hello, word');
      expect(_read(text), [
        _s('hello,', {'bold': true}),
        _s(' word'),
      ]);
    });

    test('toString shows the id and the first 20 runes', () {
      final text = open(CRDTDocument())..insert(0, '\u{1F600}' * 21);
      expect(
        text.toString(),
        'CRDTFugueRichText(rich, "${'\u{1F600}' * 20}...")',
      );
      text.delete(2, 19);
      expect(text.toString(), 'CRDTFugueRichText(rich, "\u{1F600}\u{1F600}")');
    });

    group('an insert that does not inherit', () {
      test('gets exactly its attributes', () {
        final text = open(CRDTDocument(peerId: peerA))
          ..insert(0, 'ab')
          ..format(0, 2, 'bold', true)
          ..format(0, 2, 'size', 2)
          ..insert(
            1,
            'x',
            attributes: {'size': 2, 'italic': true},
            inherit: false,
          );
        expect(_read(text), [
          _s('a', {'bold': true, 'size': 2}),
          _s('x', {'size': 2, 'italic': true}),
          _s('b', {'bold': true, 'size': 2}),
        ]);
      });

      test('writes a mark only where it changes the text', () {
        final doc = CRDTDocument(peerId: peerA);
        final text = open(doc)
          ..insert(0, 'ab')
          ..format(0, 2, 'bold', true);
        final changes = doc.exportChanges().length;

        text.insert(0, 'x', inherit: false);
        expect(doc.exportChanges(), hasLength(changes + 1));

        text.insert(3, 'y', inherit: false);
        expect(doc.exportChanges(), hasLength(changes + 3));
        expect(_read(text), [
          _s('x'),
          _s('ab', {'bold': true}),
          _s('y'),
        ]);
      });
    });

    test('text typed before an inserted run stays out of its attributes', () {
      final text = open(CRDTDocument(peerId: peerA))
        ..insert(0, 'ab')
        ..insert(1, 'x', attributes: {'bold': true})
        ..insert(1, 'y');
      expect(_read(text), [
        _s('ay'),
        _s('x', {'bold': true}),
        _s('b'),
      ]);
    });

    test('refuses a value it cannot encode', () {
      final text = open(CRDTDocument())..insert(0, 'ab');
      expect(() => text.format(0, 1, 'k', [1]), throwsArgumentError);
      expect(
        () => text.format(0, 1, 'k', 4503599627370496),
        throwsArgumentError,
      );
      expect(
        () => text.insert(0, 'x', attributes: {'k': const Object()}),
        throwsArgumentError,
      );
    });

    group('decoding refuses a broken mark', () {
      Matcher refused(String message) => throwsA(
            isA<FormatException>()
                .having((e) => e.message, 'message', contains(message)),
          );

      // Key 'k', then what follows it.
      const bodies = {
        'Truncated mark value': [1, 0x6B],
        'Unknown mark value tag 9': [1, 0x6B, 9],
        'Truncated mark double': [1, 0x6B, 4, 0, 0],
        'Truncated rich text anchor': [1, 0x6B, 0],
        'Unknown rich text anchor side 7': [1, 0x6B, 0, 7],
      };
      for (final MapEntry(key: message, value: body) in bodies.entries) {
        test('an operation: $message', () {
          final doc = CRDTDocument(peerId: peerA);
          final text = open(doc)..insert(0, 'ab');
          doc.applyChange(
            Change.fromPayloadBytes(
              id: OperationId(peerC, HybridLogicalClock(l: 100, c: 1)),
              deps: doc.version,
              author: peerC,
              payloadBytes: OperationEnvelopeCodec.encode(
                handlerType: text.handlerType,
                handlerId: text.id,
                kind: 4,
                stamped: true,
                body: Uint8List.fromList(body),
              ),
            ),
          );
          expect(() => text.value, refused(message));
        });
      }

      // The blob ends with the marks section, then its length in 4 bytes.
      Uint8List blob() {
        final source = CRDTDocument(peerId: peerA);
        open(source)
          ..insert(0, 'ab')
          ..format(0, 1, 'bold', true);
        return source.takeSnapshot().data['rich']!;
      }

      int sectionStart(Uint8List blob) =>
          blob.length -
          4 -
          ByteData.sublistView(blob, blob.length - 4).getUint32(0);

      Uint8List withTrailer(List<int> head, int length) => Uint8List.fromList(
            [
              ...head,
              ...(ByteData(4)..setUint32(0, length)).buffer.asUint8List(),
            ],
          );

      final blobs = <String, Uint8List Function(Uint8List)>{
        // Shorter than the trailer: the Fugue section refuses it first.
        'Fugue': (blob) => blob.sublist(0, 3),
        'Truncated rich text marks section': (blob) =>
            withTrailer(blob.sublist(0, blob.length - 4), blob.length),
        'Rich text marks snapshot version 2 is newer': (blob) =>
            Uint8List.fromList(blob)..[sectionStart(blob)] = 2,
        'declares': (blob) => withTrailer(
              [...blob.sublist(0, blob.length - 4), 0],
              blob.length - 4 - sectionStart(blob) + 1,
            ),
      };
      for (final MapEntry(key: message, value: corrupt) in blobs.entries) {
        test('a snapshot: $message', () {
          final restored = CRDTDocument(peerId: peerB)
            ..importSnapshot(
              Snapshot(
                id: 'broken',
                versionVector: VersionVector({}),
                data: {'rich': corrupt(blob())},
              ),
            );
          expect(() => open(restored).value, refused(message));
        });
      }
    });

    group('block attributes', () {
      test('a newline formatted alone never expands', () {
        final text = open(CRDTDocument(peerId: peerA))
          ..insert(0, 'ab\ncd')
          ..format(2, 1, 'header', 1, expand: MarkExpand.none)
          ..insert(3, 'x')
          ..insert(2, 'y');
        expect(_read(text), [
          _s('aby'),
          _s('\n', {'header': 1}),
          _s('xcd'),
        ]);

        text.format(3, 1, 'header', null, expand: MarkExpand.none);
        expect(text.attributesAt(3), isEmpty);
        text.insert(3, 'z', attributes: {'header': 1});
        expect(text.attributesAt(3), {'header': 1});
        expect(text.attributesAt(2), isEmpty, reason: 'the unmark kept out');
      });

      test('an insert anchors its newlines as blocks', () {
        final text = open(CRDTDocument(peerId: peerA))
          ..insert(0, 'ab\ncd', attributes: {'bold': true})
          ..insert(5, 'e')
          ..insert(3, 'x')
          ..insert(2, 'y');
        expect(_read(text), [
          _s('aby\n', {'bold': true}),
          _s('x'),
          _s('cde', {'bold': true}),
        ]);
      });
    });

    group('typing next to deleted text', () {
      test('stays out of a link whose last character is gone', () {
        final text = open(CRDTDocument(peerId: peerA))
          ..insert(0, 'ab')
          ..format(0, 2, 'link', 'u', expand: MarkExpand.none)
          ..delete(1, 1)
          ..insert(1, 'c');
        expect(_read(text), [
          _s('a', {'link': 'u'}),
          _s('c'),
        ]);
      });

      test('stays in a bold that expands after, out of the link', () {
        final text = open(CRDTDocument(peerId: peerA))
          ..insert(0, 'ab')
          ..format(0, 2, 'bold', true)
          ..format(0, 2, 'link', 'u', expand: MarkExpand.none)
          ..delete(1, 1)
          ..insert(1, 'c');
        expect(_read(text), [
          _s('a', {'bold': true, 'link': 'u'}),
          _s('c', {'bold': true}),
        ]);
      });

      test('two peers typing there at once converge out of the link', () {
        final a = CRDTDocument(peerId: peerA);
        final textA = open(a)
          ..insert(0, 'ab')
          ..format(0, 2, 'link', 'u', expand: MarkExpand.none)
          ..delete(1, 1);
        final b = fork(a, peerB);
        final textB = open(b);

        textA.insert(1, 'x');
        textB.insert(1, 'y');
        sync(a, b);
        sync(b, a);

        expect(_read(textA), _read(textB));
        expect(textA.text, hasLength(3));
        expect(textA.attributesAt(1), isEmpty);
        expect(textA.attributesAt(2), isEmpty);
      });

      test('lands where the Fugue text does when no mark ends there', () {
        final doc = CRDTDocument(peerId: peerA);
        final plain = CRDTFugueTextHandler(doc, 'plain')..insert(0, 'abcdef');
        final rich = open(doc)
          ..insert(0, 'abcdef')
          ..format(0, 2, 'bold', true)
          ..format(4, 2, 'link', 'u', expand: MarkExpand.none);
        // c carries the end of the bold, e the start of the link.
        final plainTombstones = [3, 5].map(plain.stablePositionAt).toList();
        final richTombstones = [3, 5].map(rich.stablePositionAt).toList();
        plain
          ..delete(4, 1)
          ..delete(2, 1)
          ..insert(2, 'X')
          ..insert(4, 'Y');
        rich
          ..delete(4, 1)
          ..delete(2, 1)
          ..insert(2, 'X')
          ..insert(4, 'Y');

        expect(rich.text, plain.value);
        for (var i = 0; i < 2; i++) {
          expect(
            rich.indexOfStablePosition(richTombstones[i]),
            plain.indexOfStablePosition(plainTombstones[i]),
            reason: 'tombstone $i',
          );
        }
        expect(rich.attributesAt(2), {'bold': true});
        expect(rich.attributesAt(4), isEmpty);
      });

      test('reads the same past a long run of tombstones', () {
        final text = open(CRDTDocument(peerId: peerA))
          ..insert(
            0,
            '${'w' * 300}a${'x' * 300}b',
            attributes: {'italic': true},
          )
          ..format(301, 300, 'bold', true, expand: MarkExpand.none);
        void edit(void Function() step) {
          text.value;
          step();
          final folded = _read(text);
          text.invalidateCache();
          expect(_read(text), folded);
        }

        edit(() => text.delete(301, 300));
        edit(() => text.delete(0, 300));
        // After the tombstone the bold ends on, then before the first one.
        edit(() => text.insert(1, 'y'));
        edit(() => text.insert(0, 'z'));
        expect(_read(text), [
          _s('z'),
          _s('ayb', {'italic': true}),
        ]);
      });
    });

    group('undo', () {
      CRDTUndoManager track(CRDTDocument doc, CRDTFugueRichTextHandler text) {
        final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
          ..track(text);
        addTearDown(undo.dispose);
        return undo;
      }

      test('undoing the delete of plain text writes only the text back', () {
        final doc = CRDTDocument(peerId: peerA);
        final text = open(doc)
          ..insert(0, 'abcd')
          ..format(0, 1, 'bold', true, expand: MarkExpand.none);
        final undo = track(doc, text);
        text.delete(2, 1);
        final changes = doc.exportChanges().length;

        undo.undo();

        expect(_read(text), [
          _s('a', {'bold': true}),
          _s('bcd'),
        ]);
        expect(doc.exportChanges(), hasLength(changes + 1));
      });

      test('a restored run is pinned where its gap gives another value', () {
        final doc = CRDTDocument(peerId: peerA);
        final text = open(doc)
          ..insert(0, 'abc')
          ..format(0, 3, 'bold', true)
          ..format(0, 3, 'bold', null)
          ..format(1, 1, 'bold', true, expand: MarkExpand.none);
        final before = _read(text);
        final undo = track(doc, text);

        text.delete(1, 1);
        undo.undo();

        expect(_read(text), before);
      });

      test('a format made over a deleted run covers it once undone', () {
        final a = CRDTDocument(peerId: peerA);
        final textA = open(a)
          ..insert(0, 'abc')
          ..format(0, 3, 'bold', true);
        final undo = track(a, textA);
        textA.delete(1, 1);
        final b = fork(a, peerB);
        open(b).format(0, 2, 'bold', null);
        sync(a, b);

        undo.undo();

        expect(_read(textA), [
          _s('abc'),
        ]);
      });
    });

    group('deltas', () {
      Future<List<RichTextDelta>> watch(
        CRDTFugueRichTextHandler text,
        void Function() edit,
      ) async {
        text.value;
        final deltas = <RichTextDelta>[];
        final subscription = text.watch().listen((update) {
          if (update is HandlerDelta<RichTextDelta>) {
            deltas.add(update.delta);
          }
        });
        await Future<void>.delayed(Duration.zero);
        edit();
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();
        return deltas;
      }

      test('an insert carries the attributes the text ends up with', () async {
        final text = open(CRDTDocument(peerId: peerA))
          ..insert(0, 'ab')
          ..format(0, 2, 'bold', true);
        final deltas = await watch(
          text,
          () => text.insert(2, 'cd', attributes: {'size': 1}),
        );
        // The text, then its own attributes: one change each.
        expect(deltas, [
          RichTextDelta([
            RichTextRetain(2),
            RichTextInsert('cd', {'bold': true}),
          ]),
          RichTextDelta([
            RichTextRetain(2),
            RichTextRetain(2, {'size': 1}),
          ]),
        ]);
        expect(
          deltas.first.compose(deltas.last),
          RichTextDelta([
            RichTextRetain(2),
            RichTextInsert('cd', {'bold': true, 'size': 1}),
          ]),
        );
      });

      test('an update keeps the attributes of what it writes over', () async {
        final text = open(CRDTDocument(peerId: peerA))
          ..insert(0, 'abc')
          ..format(1, 1, 'bold', true, expand: MarkExpand.none);
        final deltas = await watch(text, () => text.update(1, 'x'));
        expect(deltas, [
          RichTextDelta([
            RichTextRetain(1),
            RichTextInsert('x', {'bold': true}),
            const RichTextDelete(1),
          ]),
        ]);
        expect(_read(text), [
          _s('a'),
          _s('x', {'bold': true}),
          _s('c'),
        ]);
      });

      test('a mark over tombstones moves only the places it changed', () async {
        final text = open(CRDTDocument(peerId: peerA))
          ..insert(0, 'abcd')
          ..format(1, 1, 'bold', true, expand: MarkExpand.none)
          ..delete(2, 1);
        final deltas = await watch(
          text,
          () => text.format(0, 3, 'bold', true, expand: MarkExpand.none),
        );
        expect(deltas, [
          RichTextDelta([
            RichTextRetain(1, {'bold': true}),
            RichTextRetain(1),
            RichTextRetain(1, {'bold': true}),
          ]),
        ]);
      });

      test('a mark over no live text moves nothing, and still holds', () async {
        final a = CRDTDocument(peerId: peerA);
        final textA = open(a)..insert(0, 'abcd');
        final b = fork(a, peerB);
        open(b).format(1, 2, 'bold', true, expand: MarkExpand.both);
        textA.delete(1, 2);

        final deltas = await watch(textA, () => sync(a, b));
        expect(deltas, [const RichTextDelta.empty()]);

        textA.insert(1, 'x');
        expect(_read(textA), [
          _s('a'),
          _s('x', {'bold': true}),
          _s('d'),
        ]);
      });

      test('a concurrent mark moves what it changes, maybe nothing', () async {
        final a = CRDTDocument(peerId: peerA);
        final textA = open(a)
          ..insert(0, 'abcd')
          ..format(1, 2, 'bold', true, expand: MarkExpand.none);
        final b = fork(a, peerB);
        open(b).format(1, 2, 'bold', null, expand: MarkExpand.none);
        textA.format(0, 4, 'bold', true, expand: MarkExpand.none);
        final unboldWins = b.exportChanges().last.id.compareTo(
                  a.exportChanges().last.id,
                ) >
            0;

        final deltas = await watch(textA, () => sync(a, b));
        expect(deltas, [
          if (unboldWins)
            RichTextDelta([
              RichTextRetain(1),
              RichTextRetain(2, {'bold': null}),
            ])
          else
            const RichTextDelta.empty(),
        ]);
      });
    });
  });
}
