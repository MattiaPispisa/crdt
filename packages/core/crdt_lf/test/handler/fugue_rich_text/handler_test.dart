// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
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
        ..delete(3, 1);
      final restored = CRDTDocument(peerId: peerB)
        ..importSnapshot(source.takeSnapshot());
      final text = open(restored);

      expect(_read(text), [
        _s('ab', {'bold': true}),
        _s('df', {'link': 'u'}),
        _s('g'),
      ]);
      text
        ..insert(4, 'y')
        ..insert(2, 'x');
      expect(text.text, 'abxdfyg');
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

    test('indices count runes', () {
      final text = open(CRDTDocument())
        ..insert(0, '\u{1F600}a\u{1F600}b')
        ..format(1, 2, 'bold', true);
      expect(_read(text), [
        _s('\u{1F600}'),
        _s('a\u{1F600}', {'bold': true}),
        _s('b'),
      ]);
      expect(text.attributesAt(2), {'bold': true});
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
    });

    group('undo', () {
      CRDTUndoManager track(CRDTDocument doc, CRDTFugueRichTextHandler text) {
        final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
          ..track(text);
        addTearDown(undo.dispose);
        return undo;
      }

      test('a deleted run comes back with the formats it had', () {
        final doc = CRDTDocument(peerId: peerA);
        final text = open(doc)
          ..insert(0, 'xabcy')
          ..format(1, 3, 'bold', true, expand: MarkExpand.none)
          ..format(2, 1, 'link', 'u', expand: MarkExpand.none)
          ..format(4, 1, 'size', 2, expand: MarkExpand.both);
        final before = _read(text);
        final undo = track(doc, text);

        text.delete(1, 3);
        undo.undo();
        expect(_read(text), before);

        undo.redo();
        expect(text.text, 'xy');
        undo.undo();
        expect(_read(text), before);
      });

      test('an insert with attributes leaves no format behind', () {
        final doc = CRDTDocument(peerId: peerA);
        final text = open(doc)..insert(0, 'ab');
        final undo = track(doc, text);

        text.insert(1, 'xy', attributes: {'bold': true, 'size': 3});
        undo.undo();
        text.insert(1, 'z');

        expect(_read(text), [_s('azb')]);
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
