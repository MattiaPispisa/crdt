import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/snapshot/blob_version.dart';
import 'package:test/test.dart';

/// One built-in blob: the handler that writes it, the name its reader puts in
/// the error message, and the read that forces a decode.
class _Blob {
  _Blob(this.name, this.id, this.register);

  final String name;
  final String id;
  final void Function(CRDTDocument doc, {required bool seed}) register;
}

final _blobs = <_Blob>[
  _Blob('text', 'text', (doc, {required seed}) {
    final h = CRDTTextHandler(doc, 'text');
    if (seed) {
      h.insert(0, 'hello');
    } else {
      h.value;
    }
  }),
  _Blob('list', 'list', (doc, {required seed}) {
    final h = CRDTListHandler<String>(doc, 'list');
    if (seed) {
      h.insert(0, 'a');
    } else {
      h.value;
    }
  }),
  _Blob('map', 'map', (doc, {required seed}) {
    final h = CRDTMapHandler<int>(doc, 'map');
    if (seed) {
      h.set('k', 1);
    } else {
      h.value;
    }
  }),
  _Blob('register', 'register', (doc, {required seed}) {
    final h = CRDTRegisterHandler<int>(doc, 'register');
    if (seed) {
      h.set(7);
    } else {
      h.value;
    }
  }),
  _Blob('OR-set', 'or_set', (doc, {required seed}) {
    final h = CRDTORSetHandler<String>(doc, 'or_set');
    if (seed) {
      h.add('x');
    } else {
      h.value;
    }
  }),
  _Blob('OR-map', 'or_map', (doc, {required seed}) {
    final h = CRDTORMapHandler<String, int>(doc, 'or_map');
    if (seed) {
      h.put('k', 1);
    } else {
      h.value;
    }
  }),
  _Blob('Fugue', 'fugue_text', (doc, {required seed}) {
    final h = CRDTFugueTextHandler(doc, 'fugue_text');
    if (seed) {
      h.insert(0, 'hi');
    } else {
      h.value;
    }
  }),
  _Blob('movable list', 'movable', (doc, {required seed}) {
    final h = CRDTFugueMovableListHandler<String>(doc, 'movable');
    if (seed) {
      h.insert(0, 'a');
    } else {
      h.value;
    }
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

void main() {
  group('SnapshotBlob', () {
    test('refuses an empty buffer', () {
      expect(
        () => SnapshotBlob.read(Uint8List(0), version: 1, name: 'thing'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Truncated thing snapshot'),
          ),
        ),
      );
    });

    test('names both versions when it refuses one', () {
      expect(
        () => SnapshotBlob.read(
          Uint8List.fromList([9]),
          version: 1,
          name: 'thing',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('9'), contains('1')),
          ),
        ),
      );
    });

    test('returns the offset of what follows the version', () {
      expect(
        SnapshotBlob.read(
          Uint8List.fromList([1, 2, 3]),
          version: 1,
          name: 'thing',
        ),
        equals(1),
      );
    });
  });

  // `Snapshot.schemaVersion` covers the framing of the entries, not what is
  // inside one. Without a version of its own, a blob written by a build with
  // another layout is read as far as it happens to parse, and that peer ends
  // up holding a state no other peer holds.
  group('every built-in snapshot blob is versioned', () {
    test('each one leads with the version its reader expects', () {
      final snapshot = _seeded().takeSnapshot(pruneHistory: false);

      for (final blob in _blobs) {
        expect(
          snapshot.data[blob.id]![0],
          equals(1),
          reason: '${blob.id} does not lead with a version byte',
        );
      }
    });

    for (final blob in _blobs) {
      test('a ${blob.name} blob from another build is refused', () {
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
              allOf(contains(blob.name), contains('2'), contains('1')),
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
}
