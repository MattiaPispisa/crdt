import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/snapshot/blob_version.dart';
import 'package:test/test.dart';

import '../helpers/pn_counter_handler.dart';

/// One built-in blob: the handler that writes it, and the read that forces a
/// decode.
class _Blob {
  _Blob(this.name, this.id, this.register, {String? readerName})
      : _readerName = readerName;

  final String name;
  final String id;
  final Handler<dynamic> Function(CRDTDocument doc, {required bool seed})
      register;

  final String? _readerName;

  /// The name the reader puts in its error message.
  ///
  /// `Handler.readSnapshotHeader` names the handler type, which is what a peer
  /// compares. The Fugue handlers read through a shared blob helper that names
  /// the layout instead.
  late final String readerName = _readerName ??
      register(CRDTDocument(peerId: PeerId.generate()), seed: false)
          .handlerType;
}

final _blobs = <_Blob>[
  _Blob('text', 'text', (doc, {required seed}) {
    final h = CRDTTextHandler(doc, 'text');
    if (seed) {
      h.insert(0, 'hello');
    } else {
      h.value;
    }
    return h;
  }),
  _Blob('list', 'list', (doc, {required seed}) {
    final h = CRDTListHandler<String>(
      doc,
      'list',
      handlerType: 'CRDTListHandler<String>',
    );
    if (seed) {
      h.insert(0, 'a');
    } else {
      h.value;
    }
    return h;
  }),
  _Blob('map', 'map', (doc, {required seed}) {
    final h = CRDTMapHandler<int>(
      doc,
      'map',
      handlerType: 'CRDTMapHandler<int>',
    );
    if (seed) {
      h.set('k', 1);
    } else {
      h.value;
    }
    return h;
  }),
  _Blob('register', 'register', (doc, {required seed}) {
    final h = CRDTRegisterHandler<int>(
      doc,
      'register',
      handlerType: 'CRDTRegisterHandler<int>',
    );
    if (seed) {
      h.set(7);
    } else {
      h.value;
    }
    return h;
  }),
  _Blob('OR-set', 'or_set', (doc, {required seed}) {
    final h = CRDTORSetHandler<String>(
      doc,
      'or_set',
      handlerType: 'CRDTORSetHandler<String>',
    );
    if (seed) {
      h.add('x');
    } else {
      h.value;
    }
    return h;
  }),
  _Blob('OR-map', 'or_map', (doc, {required seed}) {
    final h = CRDTORMapHandler<String, int>(
      doc,
      'or_map',
      handlerType: 'CRDTORMapHandler<String, int>',
    );
    if (seed) {
      h.put('k', 1);
    } else {
      h.value;
    }
    return h;
  }),
  _Blob(readerName: 'Fugue', 'Fugue', 'fugue_text', (doc, {required seed}) {
    final h = CRDTFugueTextHandler(doc, 'fugue_text');
    if (seed) {
      h.insert(0, 'hi');
    } else {
      h.value;
    }
    return h;
  }),
  _Blob('movable list', 'movable', (doc, {required seed}) {
    final h = CRDTFugueMovableListHandler<String>(
      doc,
      'movable',
      handlerType: 'CRDTFugueMovableListHandler<String>',
    );
    if (seed) {
      h.insert(0, 'a');
    } else {
      h.value;
    }
    return h;
  }),
];

CRDTDocument _seeded() {
  final doc = CRDTDocument(peerId: PeerId.generate());
  for (final blob in _blobs) {
    blob.register(doc, seed: true);
  }
  return doc;
}

Snapshot _withBlob(Snapshot snapshot, String key, Uint8List blob) {
  return Snapshot.create(
    versionVector: snapshot.versionVector,
    data: {...snapshot.data, key: blob},
  );
}


/// A handler whose blob layout changed between two builds.
///
/// v1 stores the text raw; v2 length-prefixes it. [writes] picks which build
/// this instance stands for, and it reads both — which is the whole point of
/// `minReadableSnapshotBlobVersion`.
final class _MigratingHandler extends Handler<String> {
  _MigratingHandler(super.doc, {required this.writes});

  @override
  HandlerSpec<_MigratingHandler> get spec => HandlerSpec(
        '_MigratingHandler',
        (doc, id) => _MigratingHandler(doc, writes: writes),
        formats: HandlerFormats(
          operationKinds: const {OperationType.kindInsert},
          blobVersions: BlobVersionRange(
            minReadableSnapshotBlobVersion,
            snapshotBlobVersion,
          ),
        ),
      );

  final int writes;

  @override
  String get id => 'migrating';

  @override
  int get snapshotBlobVersion => writes;

  @override
  int get minReadableSnapshotBlobVersion => 1;

  @override
  late final OperationDecoders operationDecoders = {};

  String text = '';

  @override
  Uint8List getSnapshotState() {
    final out = snapshotHeader();
    final bytes = Wtf8.encode(text);
    if (writes >= 2) {
      UVarint.write(bytes.length, out);
    }
    out.add(bytes);
    return out.toBytes();
  }

  /// The text the last snapshot carries, whichever layout wrote it.
  String get value {
    final blob = lastSnapshot();
    if (blob == null || blob.isEmpty) {
      return '';
    }

    final head = readSnapshotHeader(blob);
    if (head.version == 1) {
      return Wtf8.decode(Uint8List.sublistView(blob, head.offset));
    }
    final len = UVarint.read(blob, offset: head.offset);
    return Wtf8.decode(
      Uint8List.sublistView(blob, len.nextOffset, len.nextOffset + len.value),
    );
  }
}

void main() {
  group('SnapshotBlob', () {
    test('refuses an empty buffer', () {
      expect(
        () => SnapshotBlob.read(Uint8List(0), min: 1, max: 1, name: 'thing'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Truncated thing snapshot'),
          ),
        ),
      );
    });

    test('a blob newer than the range asks for a newer build', () {
      expect(
        () => SnapshotBlob.read(
          Uint8List.fromList([9]),
          min: 1,
          max: 1,
          name: 'thing',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('newer'), contains('9'), contains('1')),
          ),
        ),
      );
    });

    test('a blob older than the range is a layout this build dropped', () {
      // Told apart from the case above on purpose: one needs a newer reader,
      // the other says this reader removed support it used to have.
      expect(
        () => SnapshotBlob.read(
          Uint8List.fromList([1]),
          min: 2,
          max: 3,
          name: 'thing',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('older'), contains('1')),
          ),
        ),
      );
    });

    test('accepts anything inside the range and reports which it found', () {
      // The whole point of a range: an older layout is readable, and the
      // reader is told which one it got so it can migrate.
      expect(
        SnapshotBlob.read(
          Uint8List.fromList([1, 7, 7]),
          min: 1,
          max: 3,
          name: 'thing',
        ),
        (version: 1, offset: 1),
      );
    });
  });

  // `Snapshot.schemaVersion` covers the framing of the entries, not what is
  // inside one. Without a version of its own, a blob written by a build with
  // another layout is read as far as it happens to parse, and that peer ends
  // up holding a state no other peer holds.
  group('every built-in snapshot blob is versioned', () {
    test('each one leads with the version its handler declares', () {
      final doc = _seeded();
      final snapshot = doc.takeSnapshot(pruneHistory: false);

      for (final blob in _blobs) {
        expect(
          snapshot.data[blob.id]![0],
          doc.registeredHandlers[blob.id]!.snapshotBlobVersion,
          reason: '${blob.id} does not lead with the version it declares',
        );
      }
    });

    test('defaults to 1 for a handler that declares none', () {
      // Every handler written before the version existed reads back as v1.
      final doc = CRDTDocument(peerId: PeerId.generate());

      expect(PNCounterHandler(doc, 'counter').snapshotBlobVersion, 1);
    });

    for (final blob in _blobs) {
      test('a ${blob.name} blob from a newer build is refused', () {
        final snapshot = _seeded().takeSnapshot(pruneHistory: false);
        final bumped = Uint8List.fromList(snapshot.data[blob.id]!)..[0] = 2;

        final other = CRDTDocument(peerId: PeerId.generate())
          ..importSnapshot(_withBlob(snapshot, blob.id, bumped));

        expect(
          () => blob.register(other, seed: false),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(contains(blob.readerName), contains('2'), contains('1')),
            ),
          ),
        );
      });
    }

    test('the handler manifest is refused the same way', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTMapRefHandler(doc, 'root')
          .setRef('child', CRDTTextHandler(doc, 'child'));
      final snapshot = doc.takeSnapshot(pruneHistory: false);

      final key = snapshot.data.keys.firstWhere((k) => k.contains('manifest'));
      final blob = snapshot.data[key]!;
      expect(blob[0], equals(1));

      final bumped = Uint8List.fromList(blob)..[0] = 2;
      final other = CRDTDocument(peerId: PeerId.generate())
        ..importSnapshot(_withBlob(snapshot, key, bumped));

      expect(
        other.reconstruct,
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('handler manifest'),
          ),
        ),
      );
    });
  });

  group('a handler that reads a range can migrate a blob', () {
    test('a v2 build reads a v1 blob and rewrites it as v2', () {
      // The case the range exists for. Before it, a v2 build refused a v1
      // blob outright and the peer that wrote it was turned away.
      final v1Doc = CRDTDocument(peerId: PeerId.generate());
      _MigratingHandler(v1Doc, writes: 1).text = 'written by v1';
      final v1Snapshot = v1Doc.takeSnapshot(pruneHistory: false);

      expect(v1Snapshot.data['migrating']![0], 1);

      final v2Doc = CRDTDocument(peerId: PeerId.generate())
        ..importSnapshot(v1Snapshot, pruneHistory: false);
      final v2 = _MigratingHandler(v2Doc, writes: 2);

      // Read across the layout change...
      expect(v2.value, 'written by v1');

      // ...and the next snapshot is written in the new one.
      v2.text = v2.value;
      final migrated = v2Doc.takeSnapshot(pruneHistory: false);
      expect(migrated.data['migrating']![0], 2);

      final reread = CRDTDocument(peerId: PeerId.generate())
        ..importSnapshot(migrated, pruneHistory: false);
      expect(_MigratingHandler(reread, writes: 2).value, 'written by v1');
    });

    test('a v1 build still refuses the v2 blob it cannot read', () {
      // Migration only runs forwards. The handshake check is what stops the
      // older peer from meeting this at read time.
      final v2Doc = CRDTDocument(peerId: PeerId.generate());
      _MigratingHandler(v2Doc, writes: 2).text = 'written by v2';
      final v2Snapshot = v2Doc.takeSnapshot(pruneHistory: false);

      final v1Doc = CRDTDocument(peerId: PeerId.generate())
        ..importSnapshot(v2Snapshot, pruneHistory: false);

      expect(
        () => _MigratingHandler(v1Doc, writes: 1).value,
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'message', contains('newer')),
        ),
      );
    });
  });
}
