import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

/// Oracle tests for [UndoManager]: undoing every step must bring the handler
/// back to the value it started from, and redoing every step must bring it
/// back to the value it ended on.
///
/// The point of a random walk here is the mix — inserts that split runs,
/// deletes that span several runs, updates that land on tombstones — which is
/// what a hand-written case tends to miss.
void main() {
  group('undo oracle', () {
    /// Walks [steps] states, then unwinds them and winds them back.
    void roundTrip({
      required String name,
      required Object Function(CRDTDocument doc) build,
      required void Function(Object handler, Random random, int step) edit,
      required Object? Function(Object handler) read,
      int steps = 120,
      int seed = 42,
    }) {
      test(name, () {
        final doc = CRDTDocument(peerId: PeerId.generate());
        final handler = build(doc);
        final random = Random(seed);

        final start = read(handler);
        final undo = UndoManager(
          doc,
          captureTimeout: Duration.zero,
          stackLimit: steps + 1,
        )..track(handler as Handler<dynamic>);

        final states = <Object?>[start];
        for (var i = 0; i < steps; i++) {
          edit(handler, random, i);
          states.add(read(handler));
        }
        final end = read(handler);
        expect(end, isNot(start), reason: 'the walk moved nothing');

        var unwound = 0;
        while (undo.canUndo) {
          undo.undo();
          unwound++;
          expect(unwound, lessThanOrEqualTo(steps), reason: 'undo loops');
        }
        expect(read(handler), start);

        while (undo.canRedo) {
          undo.redo();
        }
        expect(read(handler), end);
      });
    }

    roundTrip(
      name: 'CRDTFugueTextHandler',
      build: (doc) => CRDTFugueTextHandler(doc, 'text')..insert(0, 'seed text'),
      read: (handler) => (handler as CRDTFugueTextHandler).value,
      edit: (handler, random, step) {
        final text = handler as CRDTFugueTextHandler;
        final length = text.length;
        switch (length == 0 ? 0 : random.nextInt(3)) {
          case 0:
            text.insert(random.nextInt(length + 1), 'i$step');
          case 1:
            text.delete(random.nextInt(length), random.nextInt(4) + 1);
          case _:
            text.update(random.nextInt(length), 'u$step');
        }
      },
    );

    roundTrip(
      name: 'CRDTFugueTextHandler, with text outside the BMP',
      build: (doc) =>
          CRDTFugueTextHandler(doc, 'text')..insert(0, 'a\u{1F44B}b\u{1F389}c'),
      read: (handler) => (handler as CRDTFugueTextHandler).value,
      steps: 60,
      edit: (handler, random, step) {
        final text = handler as CRDTFugueTextHandler;
        final length = text.length;
        switch (length == 0 ? 0 : random.nextInt(3)) {
          case 0:
            text.insert(random.nextInt(length + 1), '\u{1F600}$step');
          case 1:
            text.delete(random.nextInt(length), random.nextInt(3) + 1);
          case _:
            text.update(random.nextInt(length), '\u{1F680}');
        }
      },
    );

    roundTrip(
      name: 'CRDTFugueListHandler',
      build: (doc) =>
          CRDTFugueListHandler<String>(doc, 'list')..insertAll(0, ['a', 'b']),
      read: (handler) =>
          List<String>.of((handler as CRDTFugueListHandler<String>).value),
      edit: (handler, random, step) {
        final list = handler as CRDTFugueListHandler<String>;
        final length = list.length;
        switch (length == 0 ? 0 : random.nextInt(3)) {
          case 0:
            list.insert(random.nextInt(length + 1), 'i$step');
          case 1:
            list.delete(random.nextInt(length), random.nextInt(3) + 1);
          case _:
            list.update(random.nextInt(length), 'u$step');
        }
      },
    );

    roundTrip(
      name: 'CRDTFugueMovableListHandler',
      build: (doc) => CRDTFugueMovableListHandler<String>(doc, 'movable')
        ..insertAll(0, ['a', 'b', 'c']),
      read: (handler) => List<String>.of(
        (handler as CRDTFugueMovableListHandler<String>).value,
      ),
      edit: (handler, random, step) {
        final list = handler as CRDTFugueMovableListHandler<String>;
        final length = list.length;
        switch (length == 0 ? 0 : random.nextInt(4)) {
          case 0:
            list.insert(random.nextInt(length + 1), 'i$step');
          case 1:
            list.delete(random.nextInt(length), random.nextInt(3) + 1);
          case 2:
            list.update(random.nextInt(length), 'u$step');
          case _:
            list.move(random.nextInt(length), random.nextInt(length));
        }
      },
    );

    roundTrip(
      name: 'CRDTMapHandler',
      build: (doc) => CRDTMapHandler<String>(doc, 'map')..set('seed', '0'),
      read: (handler) =>
          Map<String, String>.of((handler as CRDTMapHandler<String>).value),
      edit: (handler, random, step) {
        final map = handler as CRDTMapHandler<String>;
        final key = 'k${random.nextInt(6)}';
        switch (random.nextInt(3)) {
          case 0:
            map.set(key, 'v$step');
          case 1:
            map.delete(key);
          case _:
            map.update(key, 'u$step');
        }
      },
    );

    roundTrip(
      name: 'CRDTORSetHandler',
      build: (doc) => CRDTORSetHandler<String>(doc, 'set')..add('seed'),
      read: (handler) =>
          Set<String>.of((handler as CRDTORSetHandler<String>).value),
      edit: (handler, random, step) {
        final set = handler as CRDTORSetHandler<String>;
        final value = 'v${random.nextInt(6)}';
        if (random.nextBool()) {
          set.add(value);
        } else {
          set.remove(value);
        }
      },
    );

    roundTrip(
      name: 'CRDTORMapHandler',
      build: (doc) =>
          CRDTORMapHandler<String, String>(doc, 'ormap')..put('seed', '0'),
      read: (handler) => Map<String, String>.of(
        (handler as CRDTORMapHandler<String, String>).value,
      ),
      edit: (handler, random, step) {
        final map = handler as CRDTORMapHandler<String, String>;
        final key = 'k${random.nextInt(6)}';
        if (random.nextBool()) {
          map.put(key, 'v$step');
        } else {
          map.remove(key);
        }
      },
    );

    roundTrip(
      name: 'CRDTRegisterHandler',
      build: (doc) => CRDTRegisterHandler<String>(doc, 'reg')..set('seed'),
      read: (handler) => (handler as CRDTRegisterHandler<String>).value,
      edit: (handler, random, step) =>
          (handler as CRDTRegisterHandler<String>).set('v$step'),
    );
  });
}
