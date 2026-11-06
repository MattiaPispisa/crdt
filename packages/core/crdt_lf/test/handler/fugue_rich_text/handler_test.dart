// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../conformance/handler_conformance.dart';

List<List<Object?>> _read(CRDTFugueRichTextHandler text) => [
      for (final span in text.value) _s(span.text, span.attributes, span.embed),
    ];

// The rune index of each embed.
List<int> _embedIndices(CRDTFugueRichTextHandler text) {
  final indices = <int>[];
  var index = 0;
  for (final span in text.value) {
    if (span.embed != null) {
      indices.add(index);
    }
    index += span.text.runes.length;
  }
  return indices;
}

Map<String, Object?> _embedData(Random random, String token) =>
    switch (random.nextInt(3)) {
      0 => {'image': token},
      1 => {
          'video': token,
          'meta': {
            'width': random.nextInt(500),
            'ratio': 1.5,
            'tags': [token, null, true],
          },
        },
      _ => {'file': token, 'bytes': Uint8List.fromList(token.codeUnits)},
    };

Map<String, Object?> _attributes(Random random) => switch (random.nextInt(3)) {
      0 => const <String, Object?>{},
      1 => {'italic': true},
      _ => {'bold': null, 'size': random.nextInt(4)},
    };

List<Object?> _s(
  String text, [
  Map<String, Object?> attributes = const {},
  Map<String, Object?>? embed,
]) =>
    [text, attributes, if (embed != null) embed];

void main() {
  runHandlerConformanceTests(
    spec: CRDTFugueRichTextHandler.spec,
    read: _read,
    edit: (text, random, token) {
      final length = text.length;
      final embeds = _embedIndices(text);
      final runes = '\u{1F389}$token';
      final runeCount = runes.runes.length;
      // The places a rune update can start without covering an embed.
      final updatable = [
        for (var i = 0; i < length; i++)
          if (!embeds.any((at) => at >= i && at < i + runeCount)) i,
      ];
      var choice = length == 0 ? random.nextInt(2) * 5 : random.nextInt(7);
      if (choice == 2 && updatable.isEmpty) {
        choice = 0;
      }
      if (choice == 6 && embeds.isEmpty) {
        choice = 5;
      }
      switch (choice) {
        case 0:
          text.insert(
            random.nextInt(length + 1),
            random.nextInt(4) == 0 ? '\u{1F600}$token\n' : '\u{1F600}$token',
            attributes: _attributes(random),
          );
        case 1:
          text.delete(random.nextInt(length), random.nextInt(3) + 1);
        case 2:
          text.update(updatable[random.nextInt(updatable.length)], runes);
        case 5:
          text.insertEmbed(
            random.nextInt(length + 1),
            _embedData(random, token),
            attributes: _attributes(random),
            inherit: random.nextInt(3) != 0,
          );
        case 6:
          text.updateEmbed(
            embeds[random.nextInt(embeds.length)],
            _embedData(random, token),
          );
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
        case 4:
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

  CRDTUndoManager track(CRDTDocument doc, CRDTFugueRichTextHandler text) {
    final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
      ..track(text);
    addTearDown(undo.dispose);
    return undo;
  }

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

    // Pinned on purpose: a blob without embeds keeps the bytes it had before
    // embeds existed.
    test('a snapshot without embeds keeps its bytes', () {
      final doc = CRDTDocument(
        peerId: peerA,
        initialClock: HybridLogicalClock(l: 0x800000000000, c: 0),
      );
      open(doc)
        ..insert(0, 'ab\ncd')
        ..format(0, 2, 'bold', true)
        ..format(2, 1, 'header', 1, expand: MarkExpand.none)
        ..delete(3, 1);

      expect(
        doc.takeSnapshot(pruneHistory: false).data['rich'],
        equals([
          // The Fugue part.
          1, 1, 1, 0, 0, 0, 0, 0, 0, 64, 0, 128,
          0, 0, 0, 0, 0, 0, 10, 0, 5, 23, 5, 97,
          98, 10, 99, 100, 0, 0, 1, 0, 0, 0, 0, 0,
          0, 64, 0, 128, 0, 0, 0, 0, 0, 0, 10, 4,
          // The marks section.
          1, 2, 0, 0, 0, 0, 0, 0, 64, 0, 128, 0,
          0, 0, 0, 0, 0, 10, 128, 0, 0, 0, 0, 0,
          0, 3, 4, 98, 111, 108, 100, 2, 0, 1, 0, 0,
          0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0,
          0, 10, 0, 0, 1, 0, 0, 0, 0, 0, 0, 64,
          0, 128, 0, 0, 0, 0, 0, 0, 10, 2, 0, 0,
          0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0,
          0, 10, 128, 0, 0, 0, 0, 0, 0, 5, 6, 104,
          101, 97, 100, 101, 114, 3, 2, 0, 1, 0, 0, 0,
          0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0,
          10, 2, 1, 1, 0, 0, 0, 0, 0, 0, 64, 0,
          128, 0, 0, 0, 0, 0, 0, 10, 2,
          // The length of the marks section.
          0, 0, 0, 141,
        ]),
      );
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

    test('a number has the same encoding on the VM and on the web', () {
      final source = CRDTDocument(peerId: peerA);
      // dart2js cannot tell 12.0 from 12, so an integral double is an int on
      // every platform; 1e20 is past the safe int range, so it stays a double.
      open(source)
        ..insert(0, 'abc')
        ..format(0, 1, 'w', 12.0)
        ..format(1, 1, 'big', 1e20);
      final remote = CRDTDocument(peerId: peerB)
        ..importChanges(source.exportChanges());
      final remoteText = open(remote);

      expect(remoteText.attributesAt(0)['w'], isA<int>());
      expect(remoteText.attributesAt(0)['w'], 12);
      expect(remoteText.attributesAt(1)['big'], 1e20);
    });

    test('refuses a value it cannot encode', () {
      final text = open(CRDTDocument())..insert(0, 'ab');
      expect(() => text.format(0, 1, 'k', [1]), throwsArgumentError);
      // On the web this literal is a double, and a double is accepted.
      if (!identical(0, 0.0)) {
        expect(
          () => text.format(0, 1, 'k', 4503599627370496),
          throwsArgumentError,
        );
      }
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
      Uint8List blob({bool embed = false}) {
        final source = CRDTDocument(peerId: peerA);
        final text = open(source)
          ..insert(0, 'ab')
          ..format(0, 1, 'bold', true);
        if (embed) {
          text.insertEmbed(1, {'k': 1});
        }
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
        'Fugue snapshot version 2 is newer': (blob) =>
            Uint8List.fromList(blob)..[0] = 2,
        // Shorter than the trailer.
        'Truncated rich text marks': (blob) => blob.sublist(0, 3),
        'Truncated rich text marks section': (blob) =>
            withTrailer(blob.sublist(0, blob.length - 4), blob.length),
        'Rich text marks snapshot version 2 is newer': (blob) =>
            Uint8List.fromList(blob)..[sectionStart(blob)] = 2,
        'Unknown rich text embeds tag 2': (blob) => withTrailer(
              [...blob.sublist(0, blob.length - 4), 2],
              blob.length - 4 - sectionStart(blob) + 1,
            ),
        'declares': (_) {
          final embeds = blob(embed: true);
          return withTrailer(
            [...embeds.sublist(0, embeds.length - 4), 0],
            embeds.length - 4 - sectionStart(embeds) + 1,
          );
        },
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
        // The last x, where the bold ends.
        final boldEnd = text.stablePositionAt(601);
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
        // The run is longer than a plain walk goes: y still lands past it.
        expect(text.indexOfStablePosition(boldEnd), 1);
        edit(() => text.insert(0, 'z'));
        expect(_read(text), [
          _s('z'),
          _s('ayb', {'italic': true}),
        ]);
      });
    });

    group('undo', () {
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

    group('embeds', () {
      const image = <String, Object?>{'image': 'a.png'};

      FugueElementID elementAt(CRDTFugueRichTextHandler text, int index) =>
          text.stablePositionAt(index + 1);

      // Writes an operation of [kind] the public API would refuse, as peer C.
      void craft(
        CRDTDocument doc,
        CRDTFugueRichTextHandler text,
        int kind,
        List<int> body, {
        bool stamped = false,
        int clock = 1,
        int time = 0x400000000000,
      }) =>
          doc.applyChange(
            Change.fromPayloadBytes(
              id: OperationId(peerC, HybridLogicalClock(l: time, c: clock)),
              deps: doc.version,
              author: peerC,
              payloadBytes: OperationEnvelopeCodec.encode(
                handlerType: text.handlerType,
                handlerId: text.id,
                kind: kind,
                stamped: stamped,
                body: Uint8List.fromList(body),
              ),
            ),
          );

      test('an embed is one U+FFFC rune and a span of its own', () {
        final text = open(CRDTDocument(peerId: peerA))
          ..insert(0, 'ab')
          ..insertEmbed(1, image)
          ..insertEmbed(2, {'video': 'b.mp4'})
          ..format(0, 4, 'bold', true);

        expect(text.text, 'a\uFFFC\uFFFCb');
        expect(text.length, 4);
        expect(text.value, [
          RichTextSpan('a', {'bold': true}),
          RichTextSpan.embed(image, {'bold': true}),
          RichTextSpan.embed({'video': 'b.mp4'}, {'bold': true}),
          RichTextSpan('b', {'bold': true}),
        ]);
        expect(text.attributesAt(1), {'bold': true});
      });

      test('every value type crosses the wire', () {
        final data = <String, Object?>{
          'z': null,
          'f': false,
          't': true,
          'neg': -42,
          'max': 4503599627370495,
          'w': 12.0,
          'half': 1.5,
          'big': 1e20,
          'str': 'h\u{1F600}llo',
          'list': [
            1,
            [2],
          ],
          'map': {
            'b': 1,
            'a': {'c': true},
          },
          'bytes': Uint8List.fromList([0, 255]),
        };
        final source = CRDTDocument(peerId: peerA);
        open(source).insertEmbed(0, data);
        final remote = open(
          CRDTDocument(peerId: peerB)..importChanges(source.exportChanges()),
        );

        final read = remote.value.single.embed!;
        expect(read, data);
        expect(read.keys, data.keys);
        expect((read['map']! as Map).keys, ['b', 'a']);
        expect(read['w'], isA<int>());
        expect(read['big'], 1e20);
        expect(read['bytes'], isA<Uint8List>());
      });

      test('keeps a deep copy that cannot change', () {
        final list = <Object?>[1];
        final bytes = Uint8List.fromList([1]);
        final text = open(CRDTDocument())
          ..insertEmbed(0, {'list': list, 'bytes': bytes});
        list.add(2);
        bytes[0] = 9;

        final embed = text.value.single.embed!;
        expect(embed['list'], [1]);
        expect(embed['bytes'], [1]);
        expect(() => (embed['list']! as List).add(3), throwsUnsupportedError);
        expect(
          () => (embed['bytes']! as Uint8List)[0] = 2,
          throwsUnsupportedError,
        );
      });

      test('refuses data it cannot encode, before it writes', () {
        final doc = CRDTDocument();
        final text = open(doc);
        Object? nested(int depth) => depth == 0 ? 1 : [nested(depth - 1)];
        final refused = <Map<String, Object?>>[
          {'k': double.nan},
          {'k': double.infinity},
          {'k': DateTime(2020)},
          {
            'k': {1: 'a'},
          },
          {'k': nested(16)},
          if (!identical(0, 0.0)) {'k': 4503599627370496},
        ];
        for (final data in refused) {
          expect(() => text.insertEmbed(0, data), throwsArgumentError);
        }
        expect(doc.exportChanges(), isEmpty);

        text.insertEmbed(0, {'k': nested(15)});
        expect(text.length, 1);
      });

      group('decoding refuses broken data', () {
        Matcher refused(String message) => throwsA(
              isA<FormatException>()
                  .having((e) => e.message, 'message', contains(message)),
            );

        // The origins and the element, then the data.
        List<int> body(List<int> data) => [
              ...FugueElementID.nullID().toBytes(),
              ...FugueElementID.nullID().toBytes(),
              ...FugueElementID(peerC, 0).toBytes(),
              ...data,
            ];
        List<int> lists(int depth) => [
              7, 1, 1, 0x6B, // {'k': ...}
              for (var i = 1; i < depth; i++) ...[6, 1],
              0,
            ];

        final bodies = {
          'not a map': [6, 0],
          'Unknown embed value tag 9': [7, 1, 1, 0x6B, 9],
          'Truncated embed value': [7, 1, 1, 0x6B],
          'nested deeper than 16': lists(17),
        };
        for (final MapEntry(key: message, value: data) in bodies.entries) {
          test(message, () {
            final doc = CRDTDocument(peerId: peerA);
            final text = open(doc);
            craft(doc, text, 5, body(data));
            expect(() => text.value, refused(message));
          });
        }

        test('accepts 16 levels', () {
          final doc = CRDTDocument(peerId: peerA);
          final text = open(doc);
          craft(doc, text, 5, body(lists(16)));
          expect(text.value.single.embed, isNotNull);
        });
      });

      test('reads the operation layouts and every value tag', () {
        final doc = CRDTDocument(peerId: peerA);
        final text = open(doc);
        final element = FugueElementID(peerC, 0).toBytes();
        craft(doc, text, 5, [
          ...FugueElementID.nullID().toBytes(),
          ...FugueElementID.nullID().toBytes(),
          ...element,
          7, 8, // a map of 8 entries
          1, 0x6E, 0, // n: null
          1, 0x66, 1, // f: false
          1, 0x74, 2, // t: true
          1, 0x69, 3, 1, // i: -1
          1, 0x64, 4, 0x3F, 0xE0, 0, 0, 0, 0, 0, 0, // d: 0.5
          1, 0x73, 5, 1, 0x78, // s: 'x'
          1, 0x6C, 6, 1, 3, 2, // l: [1]
          1, 0x62, 8, 1, 7, // b: bytes [7]
        ]);
        expect(text.value.single.embed, {
          'n': null,
          'f': false,
          't': true,
          'i': -1,
          'd': 0.5,
          's': 'x',
          'l': [1],
          'b': Uint8List.fromList([7]),
        });

        craft(
          doc,
          text,
          6,
          [...element, 7, 1, 1, 0x6B, 0],
          stamped: true,
          clock: 2,
        );
        expect(text.value.single.embed, {'k': null});
      });

      test('maxEmbedBytes refuses a larger embed, null takes any', () {
        final doc = CRDTDocument();
        final text = open(doc);
        // A map tag, a count, a key length, 'k', a bytes tag, a 3-byte length.
        Map<String, Object?> sized(int bytes) => {'k': Uint8List(bytes - 8)};

        expect(text.maxEmbedBytes, 256 * 1024);
        text.insertEmbed(0, sized(256 * 1024));
        expect(
          () => text.insertEmbed(0, sized(256 * 1024 + 1)),
          throwsArgumentError,
        );
        expect(
          () => text.updateEmbed(0, sized(256 * 1024 + 1)),
          throwsArgumentError,
        );

        text
          ..maxEmbedBytes = null
          ..insertEmbed(0, sized(256 * 1024 + 1));
        expect(text.length, 2);

        final small = CRDTFugueRichTextHandler(
          CRDTDocument(),
          'small',
          maxEmbedBytes: 8,
        );
        // 12 bytes.
        expect(
          () => small.insertEmbed(0, {'key': '1234'}),
          throwsArgumentError,
        );
        small.insertEmbed(0, {'k': '1'});
      });

      test('checkEmbed refuses what insertEmbed refuses, and writes nothing',
          () {
        final doc = CRDTDocument();
        final text = CRDTFugueRichTextHandler(doc, 'small', maxEmbedBytes: 8);
        Object? nested(int depth) => depth == 0 ? 1 : [nested(depth - 1)];

        for (final data in <Map<String, Object?>>[
          {'k': double.nan},
          {'k': nested(16)},
          {'key': '1234'},
        ]) {
          expect(() => text.checkEmbed(data), throwsArgumentError);
          expect(() => text.insertEmbed(0, data), throwsArgumentError);
        }
        text.checkEmbed({'k': '1'});
        expect(doc.exportChanges(), isEmpty);
      });

      test('an update older than its embed changes nothing', () {
        final doc = CRDTDocument(peerId: peerA);
        final text = open(doc)..insertEmbed(0, image);
        craft(
          doc,
          text,
          6,
          [...elementAt(text, 0).toBytes(), 7, 1, 1, 0x6B, 0],
          stamped: true,
          time: 100,
        );

        expect(text.value.single.embed, image);
        expect(open(fork(doc, peerB)).value.single.embed, image);
      });

      test('concurrent embed edits on three peers converge in any order', () {
        // A literal far ahead of the wall clock: every peer keeps it and only
        // the counter moves, so the winners do not depend on the time.
        CRDTDocument peer(PeerId id) => CRDTDocument(
              peerId: id,
              initialClock: HybridLogicalClock(l: 0x800000000000, c: 0),
            );
        final base = peer(peerA);
        open(base)
          ..insert(0, 'abcd')
          ..insertEmbed(1, {'e': 1})
          ..insertEmbed(3, {'e': 2})
          ..insertEmbed(5, {'e': 3});
        final baseChanges = base.exportChanges();
        final peers = [
          for (final id in [peerA, peerB, peerC])
            peer(id)..importChanges(baseChanges),
        ];
        final [a, b, c] = peers.map(open).toList();
        // 'a', e1, 'b', e2, 'c', e3, 'd'. Each peer's first edit has the same
        // clock, so the peer id breaks the tie; a later edit wins by its clock.
        a
          ..updateEmbed(1, {'e': 1, 'by': 'a'})
          ..updateEmbed(5, {'e': 3, 'by': 'a1'})
          ..updateEmbed(5, {'e': 3, 'by': 'a2'})
          ..insertEmbed(0, {'new': 'a'});
        b
          ..updateEmbed(1, {'e': 1, 'by': 'b'})
          ..updateEmbed(5, {'e': 3, 'by': 'b'})
          ..delete(3, 1);
        c
          ..updateEmbed(1, {'e': 1, 'by': 'c'})
          ..updateEmbed(3, {'e': 2, 'by': 'c'})
          ..insertEmbed(
            0,
            {
              'new': 'c',
              'bytes': Uint8List.fromList([1, 2, 3]),
            },
            attributes: {'width': 5},
          )
          ..format(2, 1, 'bold', true);
        final edits = [
          for (final doc in peers)
            doc.exportChanges(fromVersionVector: base.getVersionVector()),
        ];

        List<List<int>> orders(List<int> items) => items.length <= 1
            ? [items]
            : [
                for (final first in items)
                  for (final rest
                      in orders([...items.where((item) => item != first)]))
                    [first, ...rest],
              ];

        final peerD = PeerId.parse('00000000-0000-4000-8000-00000000000d');
        final results = <(String, List<RichTextSpan>, Uint8List)>[];
        for (final order in orders([0, 1, 2])) {
          for (final warm in [true, false]) {
            final doc = CRDTDocument(peerId: peerD)..importChanges(baseChanges);
            final text = open(doc);
            for (final index in order) {
              if (warm) {
                text.value;
              }
              doc.importChanges(edits[index]);
            }
            final reason = '$order ${warm ? 'warm' : 'replay'}';
            final blob = doc.takeSnapshot(pruneHistory: false).data['rich']!;
            results.add((reason, text.value, blob));
          }
        }
        for (final doc in peers) {
          for (final other in peers) {
            if (other != doc) {
              sync(doc, other);
            }
          }
          final blob = doc.takeSnapshot(pruneHistory: false).data['rich']!;
          results.add(('peer ${doc.peerId}', open(doc).value, blob));
        }

        final (_, value, blob) = results.first;
        final embeds = [for (final span in value) span.embed];
        expect(embeds.whereType<Map<String, Object?>>(), hasLength(4));
        expect(embeds, contains(equals({'e': 1, 'by': 'c'})));
        expect(embeds, contains(equals({'e': 3, 'by': 'a2'})));
        expect(embeds, contains(equals({'new': 'a'})));
        expect(
          value.firstWhere((span) => span.embed?['new'] == 'c'),
          RichTextSpan.embed(
            {
              'new': 'c',
              'bytes': Uint8List.fromList([1, 2, 3]),
            },
            {'width': 5},
          ),
        );
        expect(
          value.firstWhere((span) => span.embed?['e'] == 1).attributes,
          {'bold': true},
        );
        expect(open(base).text, 'a\uFFFCb\uFFFCc\uFFFCd');
        for (final (reason, otherValue, otherBlob) in results) {
          expect(otherValue, value, reason: reason);
          expect(
            [for (final span in otherValue) span.embed],
            embeds,
            reason: reason,
          );
          expect(otherBlob, blob, reason: reason);
        }
      });

      test('a remote rune update skips the embeds it names', () {
        final doc = CRDTDocument(peerId: peerA);
        final text = open(doc)
          ..insert(0, 'a')
          ..insertEmbed(1, image);
        // Two items: 'a' to 'y', and the embed to 'x'.
        craft(
          doc,
          text,
          OperationType.kindUpdate,
          [
            2,
            ...elementAt(text, 0).toBytes(),
            1,
            0x79,
            ...elementAt(text, 1).toBytes(),
            1,
            0x78,
          ],
          stamped: true,
        );

        for (final read in [text, open(fork(doc, peerB))]) {
          expect(read.text, 'y\uFFFC');
          expect(read.value.last, RichTextSpan.embed(image));
        }
      });

      test('a U+FFFC from a crafted insert is a plain rune', () {
        final doc = CRDTDocument(peerId: peerA);
        final text = open(doc);
        craft(doc, text, OperationType.kindInsert, [
          ...FugueElementID.nullID().toBytes(),
          ...FugueElementID.nullID().toBytes(),
          1,
          ...FugueElementID(peerC, 0).toBytes(),
          3, 0xEF, 0xBF, 0xBC, // U+FFFC
        ]);
        expect(text.value, [RichTextSpan('\uFFFC')]);
        expect(() => text.updateEmbed(0, image), throwsArgumentError);
      });

      test('text never holds U+FFFC: the writes refuse it first', () {
        final doc = CRDTDocument(peerId: peerA);
        final text = open(doc)
          ..insert(0, 'ab')
          ..insertEmbed(1, image);
        final changes = doc.exportChanges().length;

        expect(() => text.insert(0, '\uFFFC'), throwsArgumentError);
        expect(() => text.update(2, '\uFFFC'), throwsArgumentError);
        expect(() => text.update(0, 'xy'), throwsArgumentError);
        expect(() => text.updateEmbed(0, image), throwsArgumentError);
        expect(() => text.updateEmbed(3, image), throwsRangeError);
        expect(doc.exportChanges(), hasLength(changes));

        text
          ..insert(3, 'c')
          ..update(2, 'x');
        expect(text.text, 'a\uFFFCxc');
      });

      group('in a snapshot', () {
        // Where [text] starts in [blob], or -1.
        int find(Uint8List blob, String text) {
          final bytes = Wtf8.encode(text);
          for (var i = 0; i + bytes.length <= blob.length; i++) {
            var j = 0;
            while (j < bytes.length && blob[i + j] == bytes[j]) {
              j++;
            }
            if (j == bytes.length) {
              return i;
            }
          }
          return -1;
        }

        test('keeps the live embeds, and nothing of a deleted one', () {
          final source = CRDTDocument(peerId: peerA);
          final text = open(source)
            ..insert(0, 'ab')
            ..insertEmbed(1, image, attributes: {'width': 10})
            ..insertEmbed(0, {'image': 'gone.png'})
            ..insertEmbed(4, {'video': 'old.mp4'})
            ..updateEmbed(4, {'video': 'new.mp4'})
            ..delete(0, 1);
          final snapshot = source.takeSnapshot();
          final restored = open(
            CRDTDocument(peerId: peerB)..importSnapshot(snapshot),
          );

          expect(restored.text, 'a\uFFFCb\uFFFC');
          expect(restored.value, text.value);
          expect(restored.value.last.embed, {'video': 'new.mp4'});
          final blob = snapshot.data['rich']!;
          expect(find(blob, 'gone.png'), -1);
          // Sorted by element id: the image was inserted first.
          expect(find(blob, 'a.png'), greaterThan(0));
          expect(find(blob, 'a.png'), lessThan(find(blob, 'new.mp4')));
        });

        test('seeds the embeds before the changes after it', () {
          final source = CRDTDocument(peerId: peerA);
          final text = open(source)
            ..insertEmbed(0, image)
            ..updateEmbed(0, {'image': 'new.png'});
          final element = elementAt(text, 0).toBytes();
          final snapshot = source.takeSnapshot();

          CRDTFugueRichTextHandler replay(
            int kind,
            List<int> body, {
            // A literal: on the web a shift is 32-bit.
            int time = 0x800000000000,
            bool warm = false,
          }) {
            final doc = CRDTDocument(peerId: peerB)..importSnapshot(snapshot);
            final text = open(doc);
            if (warm) {
              text.value;
            }
            craft(doc, text, kind, body, stamped: true, time: time);
            return text;
          }

          final older = replay(6, [...element, 7, 1, 1, 0x6B, 0], time: 100);
          expect(older.value.single.embed, {'image': 'new.png'});

          final newer = replay(6, [...element, 7, 1, 1, 0x6B, 5, 1, 0x78]);
          expect(newer.value.single.embed, {'k': 'x'});

          for (final warm in [false, true]) {
            final rune = replay(
              OperationType.kindUpdate,
              [1, ...element, 1, 0x78],
              warm: warm,
            );
            expect(rune.text, '\uFFFC', reason: 'warm: $warm');
            expect(rune.value.single.embed, {'image': 'new.png'});
          }
        });
      });

      group('undo', () {
        test('a mixed delete comes back as one chain, beside a peer edit', () {
          // The same edits with an embed or with a plain rune in the middle:
          // both give the same ids, so the same tree.
          ({
            CRDTFugueRichTextHandler a,
            CRDTFugueRichTextHandler b,
            List<(int, FugueElementID, FugueElementID)> pieces,
            List<FugueElementID> origins,
          }) run({required bool embed}) {
            final a = CRDTDocument(peerId: peerA);
            final textA = open(a)..insert(0, 'abcd');
            if (embed) {
              textA.insertEmbed(2, image, attributes: {'width': 10});
            } else {
              textA.insert(2, 'Z');
            }
            textA.format(0, 5, 'bold', true);
            final before = textA.value;
            final oldC = elementAt(textA, 3);
            final d = elementAt(textA, 4);
            final undo = track(a, textA);
            textA.delete(1, 3);
            final b = fork(a, peerB);
            final changes = a.exportChanges().length;

            undo.undo();
            expect(textA.value, before);
            final pieces = <(int, FugueElementID, FugueElementID)>[];
            for (final change in a.exportChanges().skip(changes)) {
              final bytes = change.payloadBytes();
              final envelope = OperationEnvelopeCodec.decode(bytes);
              if (envelope.kind == 4) {
                continue;
              }
              final left = FugueElementID.readFromBytes(
                bytes,
                offset: envelope.bodyOffset,
              );
              final right =
                  FugueElementID.readFromBytes(bytes, offset: left.nextOffset);
              pieces.add((envelope.kind, left.value, right.value));
            }
            final origins = [
              oldC,
              elementAt(textA, 1),
              elementAt(textA, 2),
              d,
            ];
            open(b).insert(1, 'X');
            sync(a, b);
            sync(b, a);
            return (
              a: textA,
              b: open(b),
              pieces: pieces,
              origins: origins,
            );
          }

          final plain = run(embed: false);
          final mixed = run(embed: true);

          expect(plain.pieces, hasLength(1));
          final [oldC, restoredB, restoredEmbed, d] = mixed.origins;
          expect(mixed.pieces, [
            (OperationType.kindInsert, oldC, d),
            (5, restoredB, d),
            (OperationType.kindInsert, restoredEmbed, d),
          ]);
          expect(mixed.a.text.replaceAll('\uFFFC', 'Z'), plain.a.text);
          expect(mixed.a.text, 'aXb\uFFFCcd');
          expect(mixed.b.value, mixed.a.value);
          expect(mixed.a.value, [
            RichTextSpan('aXb', {'bold': true}),
            RichTextSpan.embed(image, {'bold': true, 'width': 10}),
            RichTextSpan('cd', {'bold': true}),
          ]);
          expect(
            (mixed.a.doc as CRDTDocument).takeSnapshot().data['rich'],
            (mixed.b.doc as CRDTDocument).takeSnapshot().data['rich'],
          );
        });

        test('an undone update follows the embed through undo and redo', () {
          final doc = CRDTDocument(peerId: peerA);
          final text = open(doc)
            ..insert(0, 'ab')
            ..insertEmbed(1, image);
          final undo = track(doc, text);
          text
            ..updateEmbed(1, {'image': 'b.png'})
            ..delete(0, 3);

          undo
            ..undo()
            ..redo()
            ..undo();
          expect(text.value, [
            RichTextSpan('a'),
            RichTextSpan.embed({'image': 'b.png'}),
            RichTextSpan('b'),
          ]);
          undo.undo();
          expect(text.value[1], RichTextSpan.embed(image));
          expect(open(fork(doc, peerB)).value, text.value);
        });

        test('a delete undone across snapshots puts the embed back', () {
          final source = CRDTDocument(peerId: peerA);
          final before = (open(source)
                ..insert(0, 'ab')
                ..insertEmbed(1, image, attributes: {'width': 10}))
              .value;
          final b = CRDTDocument(peerId: peerB)
            ..importSnapshot(source.takeSnapshot());
          final textB = open(b);
          final undo = track(b, textB);
          textB.delete(1, 1);
          final c = CRDTDocument(peerId: peerC)
            ..importSnapshot(b.takeSnapshot(pruneHistory: false));
          final textC = open(c);
          expect(textC.text, 'ab');

          undo.undo();
          sync(c, b);
          expect(textB.value, before);
          expect(textC.value, before);

          undo.redo();
          sync(c, b);
          expect(textC.text, 'ab');

          undo.undo();
          sync(c, b);
          expect(textB.value, before);
          expect(textC.value, before);
        });
      });

      test('its attributes stay on the embed alone', () {
        final text = open(CRDTDocument(peerId: peerA))
          ..insert(0, 'ab')
          ..insertEmbed(1, image, attributes: {'width': 10})
          ..insert(2, 'x')
          ..insert(1, 'y');
        expect(_read(text), [
          _s('ay'),
          _s('\uFFFC', {'width': 10}, image),
          _s('xb'),
        ]);
      });

      test('inherits the formats that expand over its place', () {
        final text = open(CRDTDocument(peerId: peerA))
          ..insert(0, 'ab')
          ..format(0, 2, 'bold', true)
          ..insertEmbed(2, image)
          ..insertEmbed(3, image, inherit: false);
        expect(text.attributesAt(2), {'bold': true});
        expect(text.attributesAt(3), isEmpty);
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

      test('an embed comes as one op, its update too', () async {
        const image = <String, Object?>{'image': 'a.png'};
        final text = open(CRDTDocument(peerId: peerA))
          ..insert(0, 'ab')
          ..format(0, 2, 'bold', true);
        final deltas = await watch(text, () {
          text
            ..insertEmbed(2, image, attributes: {'width': 1})
            ..updateEmbed(2, {'image': 'b.png'})
            ..delete(2, 1);
        });
        expect(deltas, [
          RichTextDelta([
            RichTextRetain(2),
            RichTextInsertEmbed(image, {'bold': true}),
          ]),
          RichTextDelta([
            RichTextRetain(2),
            RichTextRetain(1, {'width': 1}),
          ]),
          RichTextDelta([
            RichTextRetain(2),
            RichTextUpdateEmbed({'image': 'b.png'}),
          ]),
          RichTextDelta([RichTextRetain(2), const RichTextDelete(1)]),
        ]);
      });

      test('an update that loses moves nothing', () async {
        final a = CRDTDocument(peerId: peerA);
        final textA = open(a)..insertEmbed(0, {'image': 'a.png'});
        final b = fork(a, peerB);
        open(b).updateEmbed(0, {'image': 'b.png'});
        textA.delete(0, 1);

        final deltas = await watch(textA, () => sync(a, b));
        expect(deltas, [const RichTextDelta.empty()]);
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
