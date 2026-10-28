// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

final _peerA = PeerId.parse('00000000-0000-4000-8000-00000000000a');
final _peerB = PeerId.parse('00000000-0000-4000-8000-00000000000b');

Future<void> _pump() => Future<void>.delayed(Duration.zero);

List<RichTextOp> _normal(List<RichTextSpan> spans) => RichTextDelta([
      for (final span in spans) RichTextInsert(span.text, span.attributes),
    ]).ops;

int _length(List<RichTextSpan> spans) =>
    spans.fold(0, (sum, span) => sum + span.text.runes.length);

/// An editor that keeps its own copy of the spans and talks to the handler
/// only through a [CrdtEditorBinding].
class _FakeEditor {
  _FakeEditor(
    this.document,
    this.handler, {
    bool verify = false,
    bool Function()? check,
  }) {
    binding = CrdtEditorBinding<List<RichTextSpan>, RichTextDelta>(
      onRemoteDelta: (event) {
        remoteDeltas++;
        spans = event.delta.apply(spans);
        onRemote?.call();
      },
      onReset: (value, cause) {
        resets.add((cause, pushing));
        spans = value;
      },
      verifyProjection:
          check ?? (verify ? () => _length(spans) == handler.length : null),
    );
  }

  final CRDTDocument document;
  final CRDTFugueRichTextHandler handler;
  late final CrdtEditorBinding<List<RichTextSpan>, RichTextDelta> binding;

  List<RichTextSpan> spans = [];
  int remoteDeltas = 0;
  final resets = <(ResetCause, bool)>[];
  bool pushing = false;
  void Function()? onRemote;

  void _local(RichTextDelta delta, void Function() write) {
    spans = delta.apply(spans);
    binding.push(() {
      pushing = true;
      try {
        document.runInTransaction(write);
      } finally {
        pushing = false;
      }
    });
  }

  void insert(
    int index,
    String text, [
    Map<String, Object?> attributes = const {},
  ]) {
    final length = text.runes.length;
    _local(
      RichTextDelta([RichTextRetain(index), RichTextInsert(text, attributes)]),
      () {
        // Clamped: a push made inside a burst writes on a handler that is
        // ahead of this editor.
        final at = min(index, handler.length);
        handler.insert(at, text, attributes: attributes);
        // The handler extends the marks around the caret; this editor does
        // not, so it clears what it did not ask for.
        for (var i = at; i < at + length; i++) {
          for (final key in handler.attributesAt(i).keys) {
            if (!attributes.containsKey(key)) {
              handler.format(i, 1, key, null, expand: MarkExpand.none);
            }
          }
        }
      },
    );
  }

  void delete(int index, int count) {
    _local(
      RichTextDelta([RichTextRetain(index), RichTextDelete(count)]),
      () => handler.delete(index, count),
    );
  }

  void format(int index, int count, String key, Object? value) {
    _local(
      RichTextDelta([
        RichTextRetain(index),
        RichTextRetain(count, {key: value}),
      ]),
      () => handler.format(index, count, key, value, expand: MarkExpand.none),
    );
  }
}

void main() {
  late CRDTDocument doc;
  late CRDTFugueRichTextHandler text;

  setUp(() {
    doc = CRDTDocument(peerId: _peerA);
    text = CRDTFugueRichTextHandler(doc, 'text');
  });

  CRDTDocument remotePeer() {
    final remote = CRDTDocument(peerId: _peerB);
    CRDTFugueRichTextHandler(remote, 'text');
    remote.importChanges(doc.exportChanges());
    return remote;
  }

  void sync(CRDTDocument remote) => doc.importChanges(
        remote.exportChanges(fromVersionVector: doc.getVersionVector()),
      );

  group('CrdtEditorBinding', () {
    test('seeds the editor at attach, with no second read', () async {
      text.insert(0, 'hello', attributes: {'bold': true});
      final editor = _FakeEditor(doc, text);

      editor.binding.attach(doc, 'text');
      expect(editor.spans, text.value);
      expect(editor.resets, [(ResetCause.initial, false)]);

      await _pump();
      expect(editor.resets, hasLength(1));
      expect(editor.binding.isAttached, isTrue);
      expect(editor.binding.document, doc);
      expect(editor.binding.id, 'text');
      expect(editor.binding.provider, text);
    });

    test('moves the editor by a remote delta', () async {
      text.insert(0, 'hello');
      final editor = _FakeEditor(doc, text)..binding.attach(doc, 'text');
      await _pump();

      final remote = remotePeer();
      (remote.registeredHandlers['text']! as CRDTFugueRichTextHandler)
          .format(0, 2, 'italic', true);
      sync(remote);

      expect(editor.remoteDeltas, 1);
      expect(_normal(editor.spans), _normal(text.value));
    });

    test('pushes a local edit and drops its echo', () async {
      final editor = _FakeEditor(doc, text)..binding.attach(doc, 'text');
      await _pump();

      editor
        ..insert(0, 'hello', {'bold': true})
        ..insert(5, '!')
        ..format(0, 1, 'italic', true)
        ..delete(1, 2);

      expect(editor.remoteDeltas, 0);
      expect(_normal(editor.spans), _normal(text.value));
    });

    test('a push made inside a push writes at once, its echo dropped',
        () async {
      final editor = _FakeEditor(doc, text)..binding.attach(doc, 'text');
      await _pump();

      editor.binding.push(() {
        editor.binding.push(() => text.insert(0, 'a'));
        text.insert(1, 'b');
      });

      expect(text.text, 'ab');
      expect(editor.remoteDeltas, 0);
    });

    test('pushes nothing while detached or once the handler is deleted', () {
      final editor = _FakeEditor(doc, text);
      var writes = 0;
      editor.binding.push(() => writes++);
      expect(writes, 0);

      editor.binding.attach(doc, 'text');
      doc.deleteHandler(text);
      editor.binding.push(() => writes++);
      expect(writes, 0);

      editor.binding.dispose();
      expect(editor.binding.isAttached, isFalse);
      expect(() => editor.binding.attach(doc, 'text'), throwsStateError);
    });

    test('recovers from a watcher that writes back during the push', () async {
      text.insert(0, 'a');
      final editor = _FakeEditor(doc, text, verify: true)
        ..binding.attach(doc, 'text');
      // Its write is served inside our push, tagged with our transaction's
      // origin: the binding drops it with the echo and reads afterwards.
      final watcher = text.watch().listen((update) {
        if (update is HandlerDelta && text.text == 'ab') {
          text.insert(2, 'c');
        }
      });
      addTearDown(watcher.cancel);
      await _pump();
      editor.resets.clear();

      editor.insert(1, 'b');

      expect(text.text, 'abc');
      expect(editor.remoteDeltas, 0);
      expect(editor.resets, [(ResetCause.deltasMissed, false)]);
      expect(_normal(editor.spans), _normal(text.value));
    });

    test('postpones a reset that arrives during the push', () async {
      text
        ..insert(0, 'hello')
        ..useIncrementalCacheUpdate = false;
      final editor = _FakeEditor(doc, text)..binding.attach(doc, 'text');
      await _pump();
      editor.resets.clear();

      editor.insert(5, '!');

      expect(editor.resets, [(ResetCause.cacheDropped, false)]);
      expect(_normal(editor.spans), _normal(text.value));
      expect(text.text, 'hello!');
    });

    test('replaces the content when the handler asks for a reset', () async {
      text.insert(0, 'hello');
      final editor = _FakeEditor(doc, text)..binding.attach(doc, 'text');
      await _pump();
      editor.resets.clear();

      final other = CRDTDocument(peerId: _peerB);
      CRDTFugueRichTextHandler(other, 'text').insert(0, 'other');
      doc.importSnapshot(other.takeSnapshot());

      expect(
        editor.resets.map((reset) => reset.$1),
        [ResetCause.snapshotImport],
      );
      expect(_normal(editor.spans), _normal(text.value));
    });

    test('reads again when the projection check fails', () async {
      text.insert(0, 'hello');
      var agrees = true;
      final editor = _FakeEditor(doc, text, check: () => agrees)
        ..binding.attach(doc, 'text');
      await _pump();
      editor.resets.clear();

      agrees = false;
      final remote = remotePeer();
      (remote.registeredHandlers['text']! as CRDTFugueRichTextHandler)
          .insert(0, 'X');
      sync(remote);

      expect(editor.resets, [(ResetCause.deltasMissed, false)]);
      expect(_normal(editor.spans), _normal(text.value));
    });

    test('reads after a push made while a burst is still in flight', () async {
      text.insert(0, 'hello');
      final editor = _FakeEditor(doc, text)..binding.attach(doc, 'text');
      await _pump();
      editor.resets.clear();

      final remote = remotePeer();
      (remote.registeredHandlers['text']! as CRDTFugueRichTextHandler)
        ..insert(0, 'A')
        ..insert(0, 'B')
        ..insert(0, 'C');
      editor.onRemote = () {
        editor
          ..onRemote = null
          ..insert(0, 'z');
      };
      sync(remote);

      expect(editor.resets, [(ResetCause.deltasMissed, false)]);
      expect(_normal(editor.spans), _normal(text.value));
    });

    test('resync reads the current value and skips what it covers', () async {
      text.insert(0, 'hello');
      final editor = _FakeEditor(doc, text);
      editor.binding.resync(ResetCause.initial);
      expect(editor.resets, isEmpty);

      editor.binding.attach(doc, 'text');
      await _pump();
      editor.resets.clear();
      editor.spans = [];

      final remote = remotePeer();
      (remote.registeredHandlers['text']! as CRDTFugueRichTextHandler)
        ..insert(0, 'X')
        ..insert(0, 'Y');
      // Mid-burst: the read already holds the delta still to come.
      editor.onRemote = () {
        editor
          ..onRemote = null
          ..binding.resync(ResetCause.initial);
      };
      sync(remote);

      expect(editor.resets, [(ResetCause.initial, false)]);
      expect(_normal(editor.spans), _normal(text.value));
    });

    test('follows another handler after a re-attach', () async {
      final other = CRDTFugueRichTextHandler(doc, 'other')..insert(0, 'other');
      text.insert(0, 'text');
      final editor = _FakeEditor(doc, text)..binding.attach(doc, 'text');
      await _pump();

      editor.binding
        ..attach(doc, 'text')
        ..attach(doc, 'other');
      expect(editor.spans, other.value);
      await _pump();

      text.insert(0, 'ignored ');
      other.insert(0, 'the ');
      expect(_normal(editor.spans), _normal(other.value));
    });

    // More than one seed: one stream of random edits is one sample.
    for (final seed in [7, 13, 29, 101, 997]) {
      test('tracks a random stream of edits against the handler (seed $seed)',
          () async {
        text.insert(0, 'hello world');
        final editor = _FakeEditor(doc, text)..binding.attach(doc, 'text');
        await _pump();

        final remote = remotePeer();
        final remoteText =
            remote.registeredHandlers['text']! as CRDTFugueRichTextHandler;
        final random = Random(seed);
        Map<String, Object?> attributes() => switch (random.nextInt(3)) {
              0 => const {},
              1 => {'italic': true},
              _ => {'size': random.nextInt(3)},
            };
        String typed() => random.nextInt(8) == 0
            ? '\u{1F600}'
            : String.fromCharCode(97 + random.nextInt(26));

        for (var round = 0; round < 150; round++) {
          final length = _length(editor.spans);
          switch (random.nextInt(5)) {
            case 0:
              editor.insert(random.nextInt(length + 1), typed(), attributes());
            case 1:
              if (length > 0) {
                editor.delete(random.nextInt(length), 1);
              }
            case 2:
              if (length > 0) {
                final index = random.nextInt(length);
                final count = 1 + random.nextInt(length - index);
                editor.format(
                  index,
                  count,
                  'bold',
                  random.nextBool() ? true : null,
                );
              }
            default:
              // A batch published at once and handed out one at a time.
              if (random.nextBool()) {
                remote.importChanges(
                  doc.exportChanges(
                    fromVersionVector: remote.getVersionVector(),
                  ),
                );
              }
              final count = 1 + random.nextInt(3);
              for (var i = 0; i < count; i++) {
                final remoteLength = remoteText.length;
                switch (remoteLength == 0 ? 0 : random.nextInt(4)) {
                  case 0:
                    remoteText.insert(
                      random.nextInt(remoteLength + 1),
                      String.fromCharCode(65 + random.nextInt(26)),
                      attributes: attributes(),
                    );
                  case 1:
                    remoteText.delete(random.nextInt(remoteLength), 1);
                  case 2:
                    remoteText.update(
                      random.nextInt(remoteLength),
                      String.fromCharCode(65 + random.nextInt(26)),
                    );
                  default:
                    final index = random.nextInt(remoteLength);
                    remoteText.format(
                      index,
                      1 + random.nextInt(remoteLength - index),
                      'link',
                      'r$round',
                    );
                }
              }
              if (random.nextInt(4) == 0) {
                // A local edit from inside the burst, as an editor that
                // normalizes what it receives would make.
                editor.onRemote = () {
                  editor.onRemote = null;
                  final at = random.nextInt(_length(editor.spans) + 1);
                  editor.insert(at, typed());
                };
              }
              sync(remote);
              editor.onRemote = null;
          }

          await _pump();
          expect(
            _normal(editor.spans),
            _normal(text.value),
            reason: 'round $round',
          );
        }
      });
    }
  });
}
