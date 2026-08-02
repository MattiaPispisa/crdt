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

    test('CRDTFugueListHandler', () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final list = CRDTFugueListHandler<String>(doc, 'fugue_list')
        ..useIncrementalCacheUpdate = true;
      final random = Random(42);

      expect(list.value, isEmpty);

      for (var i = 0; i < 100; i++) {
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
      final list2 = CRDTFugueListHandler<String>(doc2, 'fugue_list');
      doc2.importChanges(doc.exportChanges());
      expect(list2.value, incremental);
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

  group('remote incremental cache oracle', () {
    test('CRDTTextHandler', () {
      _remoteOracle<CRDTTextHandler>(
        create: (doc) => CRDTTextHandler(doc, 'text'),
        mutate: (text, random, i) {
          final len = text.length;
          final choice = random.nextInt(3);
          if (choice == 0 || len == 0) {
            text.insert(random.nextInt(len + 1), 'ins$i ');
          } else if (choice == 1) {
            text.delete(random.nextInt(len), random.nextInt(3) + 1);
          } else {
            text.update(random.nextInt(len), 'u$i');
          }
        },
        read: (text) => text.value,
      );
    });

    test('CRDTListHandler', () {
      _remoteOracle<CRDTListHandler<String>>(
        create: (doc) => CRDTListHandler<String>(doc, 'list'),
        mutate: (list, random, i) {
          final len = list.length;
          final choice = random.nextInt(3);
          if (choice == 0 || len == 0) {
            list.insert(random.nextInt(len + 1), 'item$i');
          } else if (choice == 1) {
            list.delete(random.nextInt(len), random.nextInt(3) + 1);
          } else {
            list.update(random.nextInt(len), 'updated$i');
          }
        },
        read: (list) => List<String>.from(list.value),
      );
    });

    test('CRDTMapHandler', () {
      _remoteOracle<CRDTMapHandler<int>>(
        create: (doc) => CRDTMapHandler<int>(doc, 'map'),
        mutate: (map, random, i) {
          final key = 'key${random.nextInt(20)}';
          final choice = random.nextInt(3);
          if (choice == 0) {
            map.set(key, i);
          } else if (choice == 1) {
            map.delete(key);
          } else {
            map.update(key, i * 10);
          }
        },
        read: (map) => Map<String, int>.from(map.value),
      );
    });

    test('CRDTRegisterHandler', () {
      _remoteOracle<CRDTRegisterHandler<int>>(
        create: (doc) => CRDTRegisterHandler<int>(doc, 'register'),
        mutate: (register, random, i) => register.set(i),
        read: (register) => register.value,
      );
    });

    test('CRDTORSetHandler', () {
      _remoteOracle<CRDTORSetHandler<String>>(
        create: (doc) => CRDTORSetHandler<String>(doc, 'set'),
        mutate: (set, random, i) {
          final current = set.value.toList();
          if (current.isEmpty || random.nextBool()) {
            set.add('value_$i');
          } else {
            set.remove(current[random.nextInt(current.length)]);
          }
        },
        read: (set) => Set<String>.from(set.value),
      );
    });

    test('CRDTORMapHandler', () {
      _remoteOracle<CRDTORMapHandler<String, int>>(
        create: (doc) => CRDTORMapHandler<String, int>(doc, 'or_map'),
        mutate: (map, random, i) {
          final key = 'key${random.nextInt(20)}';
          if (random.nextInt(3) < 2) {
            map.put(key, i);
          } else {
            map.remove(key);
          }
        },
        read: (map) => Map<String, int>.from(map.value),
      );
    });

    test('CRDTFugueTextHandler', () {
      _remoteOracle<CRDTFugueTextHandler>(
        create: (doc) => CRDTFugueTextHandler(doc, 'fugue'),
        mutate: (text, random, i) {
          final len = text.length;
          final choice = random.nextInt(3);
          if (choice == 0 || len == 0) {
            text.insert(random.nextInt(len + 1), 'ins$i ');
          } else if (choice == 1) {
            text.delete(random.nextInt(len), random.nextInt(3) + 1);
          } else {
            text.update(random.nextInt(len), 'u$i');
          }
        },
        read: (text) => text.value,
      );
    });

    test('CRDTFugueMovableListHandler', () {
      _remoteOracle<CRDTFugueMovableListHandler<String>>(
        create: (doc) =>
            CRDTFugueMovableListHandler<String>(doc, 'movable_list'),
        mutate: (list, random, i) {
          final len = list.length;
          final choice = random.nextInt(4);
          if (choice == 0 || len == 0) {
            list.insert(random.nextInt(len + 1), 'item$i');
          } else if (choice == 1) {
            list.move(random.nextInt(len), random.nextInt(len));
          } else if (choice == 2) {
            list.update(random.nextInt(len), 'updated$i');
          } else {
            list.delete(random.nextInt(len));
          }
        },
        read: (list) => List<String>.from(list.value),
      );
    });

    test('CRDTFugueListHandler fed one change at a time by applyChange', () {
      final source = CRDTDocument(peerId: PeerId.generate());
      final sourceList = CRDTFugueListHandler<String>(source, 'fugue_list');

      final queued = CRDTDocument(peerId: PeerId.generate());
      final queuedList = CRDTFugueListHandler<String>(queued, 'fugue_list');
      expect(queuedList.value, isEmpty);

      final random = Random(11);
      for (var i = 0; i < 100; i++) {
        final len = sourceList.length;
        final choice = random.nextInt(3);
        if (choice == 0 || len == 0) {
          sourceList.insert(random.nextInt(len + 1), 'item$i');
        } else if (choice == 1) {
          sourceList.delete(random.nextInt(len), random.nextInt(3) + 1);
        } else {
          sourceList.update(random.nextInt(len), 'updated$i');
        }

        // The single-change path, the one that never decodes the envelope.
        final pending = source
            .exportChanges(fromVersionVector: queued.getVersionVector())
            .sorted();
        for (final change in pending) {
          queued.applyChange(change);
        }
      }

      final incremental = List<String>.from(queuedList.value);
      expect(incremental, sourceList.value);

      queuedList.invalidateCache();
      expect(queuedList.value, incremental);
    });

    // Convergence itself is covered by the handler tests. What is new here is
    // that each peer keeps editing locally while remote changes are queued, so
    // a local operation has to land on an already drained state.
    test('local edits meet queued remote changes', () {
      _concurrentOracle<CRDTFugueTextHandler>(
        create: (doc) => CRDTFugueTextHandler(doc, 'fugue'),
        mutate: (text, random, round) {
          final len = text.length;
          if (len == 0 || random.nextBool()) {
            text.insert(random.nextInt(len + 1), 'r$round');
          } else {
            text.delete(random.nextInt(len), random.nextInt(2) + 1);
          }
        },
        read: (text) => text.value,
      );
    });

    test('CRDTORSetHandler under concurrent editing', () {
      _concurrentOracle<CRDTORSetHandler<String>>(
        create: (doc) => CRDTORSetHandler<String>(doc, 'set'),
        mutate: (set, random, round) {
          final current = set.value.toList();
          if (current.isEmpty || random.nextBool()) {
            set.add('value_${random.nextInt(20)}');
          } else {
            set.remove(current[random.nextInt(current.length)]);
          }
        },
        read: (set) => Set<String>.from(set.value),
      );
    });

    test('CRDTORMapHandler under concurrent editing', () {
      _concurrentOracle<CRDTORMapHandler<String, int>>(
        create: (doc) => CRDTORMapHandler<String, int>(doc, 'or_map'),
        mutate: (map, random, round) {
          final key = 'key${random.nextInt(10)}';
          if (random.nextInt(3) < 2) {
            map.put(key, round);
          } else {
            map.remove(key);
          }
        },
        read: (map) => Map<String, int>.from(map.value),
      );
    });
  });

  // A replay-order handler drops its cache here instead of folding, so what is
  // under test is the other half of the rule: the recompute that follows must
  // land on the same state the folding peers hold. Seed 19 is picked because
  // folding a change from the past would visibly break each handler below.
  group('concurrent editing without a surviving cache', () {
    test('CRDTTextHandler', () {
      _concurrentOracle<CRDTTextHandler>(
        create: (doc) => CRDTTextHandler(doc, 'text'),
        mutate: (text, random, round) {
          final len = text.length;
          if (len == 0 || random.nextBool()) {
            text.insert(random.nextInt(len + 1), 'r$round');
          } else {
            text.delete(random.nextInt(len), 1);
          }
        },
        read: (text) => text.value,
        keepsCache: false,
        seed: 19,
      );
    });

    test('CRDTListHandler', () {
      _concurrentOracle<CRDTListHandler<String>>(
        create: (doc) => CRDTListHandler<String>(doc, 'list'),
        mutate: (list, random, round) {
          final len = list.length;
          if (len == 0 || random.nextBool()) {
            list.insert(random.nextInt(len + 1), 'r$round');
          } else {
            list.delete(random.nextInt(len), 1);
          }
        },
        read: (list) => List<String>.from(list.value),
        keepsCache: false,
        seed: 19,
      );
    });

    test('CRDTMapHandler', () {
      _concurrentOracle<CRDTMapHandler<int>>(
        create: (doc) => CRDTMapHandler<int>(doc, 'map'),
        mutate: (map, random, round) {
          final key = 'key${random.nextInt(8)}';
          if (random.nextInt(3) < 2) {
            map.set(key, round);
          } else {
            map.delete(key);
          }
        },
        read: (map) => Map<String, int>.from(map.value),
        keepsCache: false,
        seed: 19,
      );
    });

    test('CRDTRegisterHandler', () {
      _concurrentOracle<CRDTRegisterHandler<int>>(
        create: (doc) => CRDTRegisterHandler<int>(doc, 'register'),
        // Each peer must write its own values, otherwise the two writes of a
        // round are indistinguishable and last-writer-wins proves nothing.
        mutate: (register, random, round) => register.set(random.nextInt(1000)),
        read: (register) => register.value,
        keepsCache: false,
        seed: 19,
      );
    });

    test('CRDTFugueMovableListHandler', () {
      _concurrentOracle<CRDTFugueMovableListHandler<String>>(
        create: (doc) =>
            CRDTFugueMovableListHandler<String>(doc, 'movable_list'),
        mutate: (list, random, round) {
          final len = list.length;
          final choice = random.nextInt(3);
          if (choice == 0 || len == 0) {
            list.insert(random.nextInt(len + 1), 'r$round');
          } else if (choice == 1) {
            list.move(random.nextInt(len), random.nextInt(len));
          } else {
            list.delete(random.nextInt(len));
          }
        },
        read: (list) => List<String>.from(list.value),
        keepsCache: false,
        seed: 19,
      );
    });
  });
}

/// Pinned peer ids for the concurrent oracle, in ascending order.
const _peerIdA = '00000000-0000-4000-8000-00000000000a';
const _peerIdB = '00000000-0000-4000-8000-00000000000b';
const _peerIdC = '00000000-0000-4000-8000-00000000000c';

/// Drives a source handler through random operations and feeds its changes to
/// two peers: one that advances its cached state as the changes arrive, one
/// forced to replay the whole history on every read. They must never disagree.
///
/// [read] must return a value that is safe to compare later, so callers copy
/// mutable states.
void _remoteOracle<H extends Handler<dynamic>>({
  required H Function(CRDTDocument doc) create,
  required void Function(H handler, Random random, int round) mutate,
  required Object? Function(H handler) read,
  int rounds = 100,
  int seed = 7,
}) {
  final source = CRDTDocument(peerId: PeerId.generate());
  final sourceHandler = create(source);

  final queued = CRDTDocument(peerId: PeerId.generate());
  final queuedHandler = create(queued);
  final recomputed = CRDTDocument(peerId: PeerId.generate());
  final recomputedHandler = create(recomputed)
    ..useIncrementalCacheUpdate = false;

  // Warm the caches: a handler with nothing cached has nothing to advance.
  read(queuedHandler);
  read(recomputedHandler);

  final random = Random(seed);
  for (var round = 0; round < rounds; round++) {
    mutate(sourceHandler, random, round);

    queued.importChanges(
      source.exportChanges(fromVersionVector: queued.getVersionVector()),
    );
    recomputed.importChanges(
      source.exportChanges(fromVersionVector: recomputed.getVersionVector()),
    );

    // Read only now and then, so the queue also gets to hold several changes
    // at once.
    if (round % 5 == 4) {
      expect(read(queuedHandler), read(recomputedHandler));
    }
  }

  final incremental = read(queuedHandler);
  expect(incremental, read(sourceHandler));
  expect(read(recomputedHandler), incremental);

  // The state built by folding must equal the state built by replaying.
  queuedHandler.invalidateCache();
  expect(read(queuedHandler), incremental);
}

/// Drives two peers that edit at the same time and exchange changes both ways,
/// against a third peer that never advances a cached state.
///
/// Each side receives changes that sort before what it already folded in. A
/// handler that opts into commutativity keeps its cache here ([keepsCache]);
/// any other one drops it and replays. Either way the three peers must agree,
/// and the folded state must equal the replayed one.
void _concurrentOracle<H extends Handler<dynamic>>({
  required H Function(CRDTDocument doc) create,
  required void Function(H handler, Random random, int round) mutate,
  required Object? Function(H handler) read,
  bool keepsCache = true,
  int rounds = 40,
  int seed = 23,
}) {
  // Pinned peer ids: they are the tie-break of the replay order, so leaving
  // them random would make every run interleave the two peers differently.
  final a = CRDTDocument(peerId: PeerId.parse(_peerIdA));
  final aHandler = create(a);
  final b = CRDTDocument(peerId: PeerId.parse(_peerIdB));
  final bHandler = create(b);
  final replay = CRDTDocument(peerId: PeerId.parse(_peerIdC));
  final replayHandler = create(replay)..useIncrementalCacheUpdate = false;

  // Warm the caches: a handler with nothing cached has nothing to advance.
  read(aHandler);
  read(bHandler);
  read(replayHandler);

  final random = Random(seed);
  for (var round = 0; round < rounds; round++) {
    mutate(aHandler, random, round);
    mutate(bHandler, random, round);

    a.importChanges(b.exportChanges(fromVersionVector: a.getVersionVector()));
    b.importChanges(a.exportChanges(fromVersionVector: b.getVersionVector()));
    replay
      ..importChanges(
        a.exportChanges(fromVersionVector: replay.getVersionVector()),
      )
      ..importChanges(
        b.exportChanges(fromVersionVector: replay.getVersionVector()),
      );

    if (keepsCache) {
      // Check before reading: a read rebuilds the cache and would hide an
      // import that dropped it.
      expect(aHandler.cachedState, isNotNull, reason: 'round $round');
      expect(bHandler.cachedState, isNotNull, reason: 'round $round');
    }

    // Both sides, not just one: the peer with the lower id sees the changes of
    // the other as newer, so only the other one takes the from-the-past path.
    final replayed = read(replayHandler);
    expect(read(aHandler), replayed, reason: 'round $round, peer a');
    expect(read(bHandler), replayed, reason: 'round $round, peer b');
  }

  final value = read(aHandler);
  expect(read(bHandler), value);
  expect(read(replayHandler), value);

  aHandler.invalidateCache();
  bHandler.invalidateCache();
  expect(read(aHandler), value);
  expect(read(bHandler), value);
}
