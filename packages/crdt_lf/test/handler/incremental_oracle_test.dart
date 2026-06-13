import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

/// Oracle tests: the incrementally-updated cached state must be identical
/// to the state recomputed from scratch (cache invalidated) and to the
/// state computed by a fresh document importing the same changes.
void main() {
  group('incremental cache oracle', () {
    test('CRDTTextHandler', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final text = CRDTTextHandler(doc, 'text')
        ..useIncrementalCacheUpdate = true;
      final random = Random(42);

      // Warm the cache so increments apply from the start
      expect(text.value, '');

      for (var i = 0; i < 200; i++) {
        final len = text.value.length;
        final choice = random.nextInt(3);
        if (choice == 0 || len == 0) {
          text.insert(random.nextInt(len + 1), 'ins$i ');
        } else if (choice == 1) {
          text.delete(random.nextInt(len), random.nextInt(5) + 1);
        } else {
          text.update(random.nextInt(len), 'up$i');
        }
      }

      final incremental = text.value;
      text.invalidateCache();
      expect(text.value, incremental);

      final doc2 = CRDTDocument(peerId: PeerId.generate());
      final text2 = CRDTTextHandler(doc2, 'text');
      doc2.importChanges(doc.exportChanges());
      expect(text2.value, incremental);
    });

    test('CRDTListHandler', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final list = CRDTListHandler<String>(doc, 'list')
        ..useIncrementalCacheUpdate = true;
      final random = Random(42);

      expect(list.value, isEmpty);

      for (var i = 0; i < 200; i++) {
        final len = list.value.length;
        final choice = random.nextInt(3);
        if (choice == 0 || len == 0) {
          list.insert(random.nextInt(len + 1), 'item$i');
        } else if (choice == 1) {
          list.delete(random.nextInt(len), random.nextInt(3) + 1);
        } else {
          list.update(random.nextInt(len), 'updated$i');
        }
      }

      final incremental = List<String>.from(list.value);
      list.invalidateCache();
      expect(list.value, incremental);

      final doc2 = CRDTDocument(peerId: PeerId.generate());
      final list2 = CRDTListHandler<String>(doc2, 'list');
      doc2.importChanges(doc.exportChanges());
      expect(list2.value, incremental);
    });

    test('CRDTMapHandler', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final map = CRDTMapHandler<int>(doc, 'map')
        ..useIncrementalCacheUpdate = true;
      final random = Random(42);

      expect(map.value, isEmpty);

      for (var i = 0; i < 200; i++) {
        final key = 'key${random.nextInt(30)}';
        final choice = random.nextInt(3);
        if (choice == 0) {
          map.set(key, i);
        } else if (choice == 1) {
          map.delete(key);
        } else {
          map.update(key, i * 10);
        }
      }

      final incremental = Map<String, int>.from(map.value);
      map.invalidateCache();
      expect(map.value, incremental);

      final doc2 = CRDTDocument(peerId: PeerId.generate());
      final map2 = CRDTMapHandler<int>(doc2, 'map');
      doc2.importChanges(doc.exportChanges());
      expect(map2.value, incremental);
    });

    test('CRDTORSetHandler', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final set = CRDTORSetHandler<String>(doc, 'set')
        ..useIncrementalCacheUpdate = true;
      final random = Random(42);
      final existing = <String>[];

      expect(set.value, isEmpty);

      for (var i = 0; i < 200; i++) {
        if (random.nextBool() || existing.isEmpty) {
          final value = 'value_$i';
          existing.add(value);
          set.add(value);
        } else {
          final value = existing.removeAt(random.nextInt(existing.length));
          set.remove(value);
        }
      }

      final incremental = Set<String>.from(set.value);
      set.invalidateCache();
      expect(set.value, incremental);

      final doc2 = CRDTDocument(peerId: PeerId.generate());
      final set2 = CRDTORSetHandler<String>(doc2, 'set');
      doc2.importChanges(doc.exportChanges());
      expect(set2.value, incremental);
    });

    test('CRDTORMapHandler', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final map = CRDTORMapHandler<String, int>(doc, 'or_map')
        ..useIncrementalCacheUpdate = true;
      final random = Random(42);

      expect(map.value, isEmpty);

      for (var i = 0; i < 200; i++) {
        final key = 'key${random.nextInt(30)}';
        if (random.nextInt(3) < 2) {
          map.put(key, i);
        } else {
          map.remove(key);
        }
      }

      final incremental = Map<String, int>.from(map.value);
      map.invalidateCache();
      expect(map.value, incremental);

      final doc2 = CRDTDocument(peerId: PeerId.generate());
      final map2 = CRDTORMapHandler<String, int>(doc2, 'or_map');
      doc2.importChanges(doc.exportChanges());
      expect(map2.value, incremental);
    });

    test('CRDTFugueTextHandler', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final text = CRDTFugueTextHandler(doc, 'fugue')
        ..useIncrementalCacheUpdate = true;
      final random = Random(42);

      expect(text.value, '');

      for (var i = 0; i < 100; i++) {
        final len = text.value.length;
        final choice = random.nextInt(3);
        if (choice == 0 || len == 0) {
          text.insert(random.nextInt(len + 1), 'ins$i ');
        } else if (choice == 1) {
          text.delete(random.nextInt(len), random.nextInt(3) + 1);
        } else {
          text.update(random.nextInt(len), 'u$i');
        }
      }

      final incremental = text.value;
      text.invalidateCache();
      expect(text.value, incremental);

      final doc2 = CRDTDocument(peerId: PeerId.generate());
      final text2 = CRDTFugueTextHandler(doc2, 'fugue');
      doc2.importChanges(doc.exportChanges());
      expect(text2.value, incremental);
    });

    test('snapshot state matches after incremental updates', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final set = CRDTORSetHandler<String>(doc, 'set')
        ..useIncrementalCacheUpdate = true;

      expect(set.value, isEmpty);
      set
        ..add('a')
        ..add('b')
        ..remove('a')
        ..add('c');

      final incrementalSnapshot = set.getSnapshotState();
      set.invalidateCache();
      expect(set.getSnapshotState(), incrementalSnapshot);
    });
  });
}
