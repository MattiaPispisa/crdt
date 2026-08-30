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
    /// Walks [steps] states, then checks every one of them again on the way
    /// back and on the way forward.
    ///
    /// [edit] must always make a step: an operation with no observable effect
    /// has an empty inverse and records nothing, which would put the model out
    /// of step with the stack.
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

        final undo = UndoManager(
          doc,
          captureTimeout: Duration.zero,
          stackLimit: steps + 1,
        )..track(handler as Handler<dynamic>);

        final states = <Object?>[read(handler)];
        for (var i = 0; i < steps; i++) {
          edit(handler, random, i);
          states.add(read(handler));
        }
        expect(
          states.last,
          isNot(states.first),
          reason: 'the walk moved nothing',
        );

        // Back down, one step at a time: every state has to come round again.
        for (var i = states.length - 1; i > 0; i--) {
          expect(read(handler), states[i], reason: 'before undo to $i');
          expect(undo.canUndo, isTrue, reason: 'the stack is short at $i');
          undo.undo();
        }
        expect(read(handler), states.first);
        expect(undo.canUndo, isFalse, reason: 'the stack is long');

        // And back up.
        for (var i = 1; i < states.length; i++) {
          expect(undo.canRedo, isTrue, reason: 'no redo for $i');
          undo.redo();
          expect(read(handler), states[i], reason: 'after redo to $i');
        }
        expect(undo.canRedo, isFalse);
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
        // A move needs two places to choose from, and one that is not the one
        // the element already holds: either writes nothing.
        switch (length == 0 ? 0 : random.nextInt(length < 2 ? 3 : 4)) {
          case 0:
            list.insert(random.nextInt(length + 1), 'i$step');
          case 1:
            list.delete(random.nextInt(length), random.nextInt(3) + 1);
          case 2:
            list.update(random.nextInt(length), 'u$step');
          case _:
            final from = random.nextInt(length);
            list.move(from, (from + 1 + random.nextInt(length - 1)) % length);
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
        // `delete` and `update` of a key that is not there change nothing.
        final present = map.value.keys.toList();
        switch (present.isEmpty ? 0 : random.nextInt(3)) {
          case 0:
            map.set('k${random.nextInt(6)}', 'v$step');
          case 1:
            map.delete(present[random.nextInt(present.length)]);
          case _:
            map.update(present[random.nextInt(present.length)], 'u$step');
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
        // Removing a value that is not in the set changes nothing.
        final present = set.value.toList();
        if (present.isEmpty || random.nextBool()) {
          set.add('v${random.nextInt(6)}');
        } else {
          set.remove(present[random.nextInt(present.length)]);
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
        // Removing a key that is not there changes nothing.
        final present = map.value.keys.toList();
        if (present.isEmpty || random.nextBool()) {
          map.put('k${random.nextInt(6)}', 'v$step');
        } else {
          map.remove(present[random.nextInt(present.length)]);
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
