// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  final peerA = PeerId.parse('00000000-0000-4000-8000-00000000000a');
  final peerB = PeerId.parse('00000000-0000-4000-8000-00000000000b');

  CRDTFugueRichTextHandler open(CRDTDocument doc) =>
      doc.handler(CRDTFugueRichTextHandler.spec, 'rich');

  final cat = Uri.parse('https://example.com/cat.png');
  final clip = Uri.parse('https://example.com/clip.mp4');

  group('RichTextImage', () {
    test('round trips its data, unknown keys included', () {
      final data = <String, Object?>{
        'type': 'image',
        'src': 'https://example.com/ä b.png',
        'alt': '',
        'title': 'A cat',
        'width': 640,
        'height': 480.0,
        'mime': 'image/png',
        'app': {
          'id': 7,
          'tags': ['x', null],
        },
      };
      final image = RichTextImage.fromEmbed(data)!;

      expect(image.src, Uri.parse('https://example.com/ä b.png'));
      expect(image.alt, '');
      expect(image.title, 'A cat');
      expect(image.width, 640);
      expect(image.height, 480);
      expect(image.mime, 'image/png');
      expect(image.toEmbed(), data);
      expect(
        image.copyWith(alt: 'A cat on a mat').toEmbed(),
        {...data, 'alt': 'A cat on a mat'},
      );
      expect(
        RichTextImage.fromEmbed({'type': 'image', 'src': 'cat.png'}),
        RichTextImage(src: Uri.parse('cat.png')),
      );
    });

    test('fromEmbed returns null for data that is not a valid image', () {
      final bad = <Map<String, Object?>>[
        {'src': 'a.png'},
        {'type': 'video', 'src': 'a.png'},
        {'type': 'image'},
        {'type': 'image', 'src': ''},
        {'type': 'image', 'src': 3},
        {'type': 'image', 'src': 'http://[::1'},
        {'type': 'image', 'src': 'data:image/png;base64,AAAA'},
        {'type': 'image', 'src': 'a.png', 'alt': null},
        {'type': 'image', 'src': 'a.png', 'alt': 1},
        {'type': 'image', 'src': 'a.png', 'title': true},
        {'type': 'image', 'src': 'a.png', 'mime': 1},
        {'type': 'image', 'src': 'a.png', 'width': 10},
        {'type': 'image', 'src': 'a.png', 'height': 10},
        {'type': 'image', 'src': 'a.png', 'width': 0, 'height': 10},
        {'type': 'image', 'src': 'a.png', 'width': 10, 'height': -1},
        {'type': 'image', 'src': 'a.png', 'width': 1.5, 'height': 10},
        {'type': 'image', 'src': 'a.png', 'width': '10', 'height': 10},
        {'type': 'image', 'src': 'a.png', 'width': double.nan, 'height': 1},
        {'type': 'image', 'src': 'a.png', 'width': 1e300, 'height': 1},
      ];
      for (final data in bad) {
        expect(RichTextImage.fromEmbed(data), isNull, reason: '$data');
      }
    });

    test('refuses an empty or data: src and a one-sided or empty size', () {
      expect(() => RichTextImage(src: Uri()), throwsArgumentError);
      expect(
        () => RichTextImage(src: Uri.parse('data:image/png;base64,AAAA')),
        throwsArgumentError,
      );
      expect(() => RichTextImage(src: cat, width: 10), throwsArgumentError);
      expect(
        () => RichTextImage(src: cat, width: 10, height: 0),
        throwsArgumentError,
      );
      expect(RichTextImage(src: cat, alt: '').alt, '');
    });
  });

  group('RichTextVideo', () {
    test('round trips its data, unknown keys included', () {
      final data = <String, Object?>{
        'type': 'video',
        'src': 'https://example.com/clip.mp4',
        'poster': 'https://example.com/clip.jpg',
        'title': 'A clip',
        'width': 1920,
        'height': 1080,
        'mime': 'video/mp4',
        'app': 'kept',
      };
      final video = RichTextVideo.fromEmbed(data)!;

      expect(video.poster, Uri.parse('https://example.com/clip.jpg'));
      expect(video.toEmbed(), data);
      expect(
        video.copyWith(title: 'B').toEmbed(),
        {...data, 'title': 'B'},
      );
    });

    test('fromEmbed returns null for data that is not a valid video', () {
      final bad = <Map<String, Object?>>[
        {'type': 'image', 'src': 'a.mp4'},
        {'type': 'video', 'src': 'a.mp4', 'poster': 1},
        {'type': 'video', 'src': 'a.mp4', 'poster': 'data:image/png,AA'},
        {'type': 'video', 'src': 'a.mp4', 'width': 10},
      ];
      for (final data in bad) {
        expect(RichTextVideo.fromEmbed(data), isNull, reason: '$data');
      }
    });

    test('refuses a data: poster', () {
      expect(
        () => RichTextVideo(src: clip, poster: Uri.parse('data:,x')),
        throwsArgumentError,
      );
    });
  });

  group('insertImage and insertVideo', () {
    test('an inline image carries the attributes and displayWidth', () {
      final text = open(CRDTDocument(peerId: peerA))
        ..insert(0, 'ab')
        ..insertImage(
          1,
          cat,
          alt: 'A cat',
          displayWidth: 320,
          attributes: {'bold': true},
        );

      expect(text.text, 'a￼b');
      final span = text.value[1];
      expect(span.image, RichTextImage(src: cat, alt: 'A cat'));
      expect(span.video, isNull);
      expect(span.attributes, {'bold': true, 'displayWidth': 320});
      expect(span.displayWidth, 320);
    });

    test('a block video gets its own line, undone in one step', () {
      final doc = CRDTDocument(peerId: peerA);
      final text = open(doc)..insert(0, 'ab');
      final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
        ..track(text);
      addTearDown(undo.dispose);

      text.insertVideo(
        1,
        clip,
        displayWidth: 640,
        attributes: {'align': 'center'},
      );

      expect(text.text, 'a￼\nb');
      expect(text.value[1].video, RichTextVideo(src: clip));
      expect(text.value[1].attributes, {'displayWidth': 640});
      expect(text.attributesAt(2), {'align': 'center'});

      undo.undo();
      expect(text.text, 'ab');
    });

    test('invalid input throws before anything is written', () {
      final doc = CRDTDocument(peerId: peerA);
      final text = open(doc)
        ..insert(0, 'ab')
        ..maxEmbedBytes = 100;
      final changes = doc.changeCountForHandler(text.id);
      final calls = <void Function()>[
        () => text.insertImage(0, Uri.parse('data:image/png;base64,AA')),
        () => text.insertImage(0, cat, width: 10),
        () => text.insertImage(0, cat, displayWidth: 0),
        () => text.insertVideo(0, clip, displayWidth: double.infinity),
        () => text.insertImage(0, cat, title: 'x' * 200),
        () => text.insertVideo(0, clip, title: 'x' * 200),
        () => text.insertImage(0, cat, attributes: {'bad': <int>[]}),
        () => text.insertVideo(0, clip, attributes: {'bad': <int>[]}),
      ];
      for (final call in calls) {
        expect(call, throwsArgumentError);
      }
      expect(doc.changeCountForHandler(text.id), changes);
      expect(text.text, 'ab');
    });

    test('displayWidth is a mark', () {
      final text = open(CRDTDocument(peerId: peerA))..insertImage(0, cat);
      expect(text.value.single.displayWidth, isNull);

      text.format(0, 1, richTextDisplayWidthKey, 480.5);
      expect(text.value.single.displayWidth, 480.5);

      text.format(0, 1, richTextDisplayWidthKey, null);
      expect(text.value.single.displayWidth, isNull);
    });
  });

  test('the media survive a remote sync and a snapshot', () {
    final a = CRDTDocument(peerId: peerA);
    open(a)
      ..insert(0, 'ab')
      ..insertImage(1, cat, width: 4, height: 3, displayWidth: 200)
      ..insertVideo(0, clip, poster: cat, attributes: {'align': 'right'});
    final expected = open(a).value;

    final remote = CRDTDocument(peerId: peerB)
      ..importChanges(a.exportChanges());
    final restored = CRDTDocument(peerId: peerB)
      ..importSnapshot(a.takeSnapshot());

    for (final doc in [remote, restored]) {
      final spans = open(doc).value;
      expect(spans, expected);
      expect(spans[0].video, RichTextVideo(src: clip, poster: cat));
      expect(spans[3].image, RichTextImage(src: cat, width: 4, height: 3));
      expect(spans[3].displayWidth, 200);
    }
  });

  test('updateEmbed with a copy keeps the keys another app added', () {
    final text = open(CRDTDocument(peerId: peerA))
      ..insertEmbed(0, {
        'type': 'image',
        'src': 'https://example.com/cat.png',
        'app': {'id': 7},
      });
    final image = text.value.single.image!;

    text.updateEmbed(0, image.copyWith(alt: 'A cat').toEmbed());

    expect(text.value.single.embed, {
      'type': 'image',
      'src': 'https://example.com/cat.png',
      'alt': 'A cat',
      'app': {'id': 7},
    });
  });
}
