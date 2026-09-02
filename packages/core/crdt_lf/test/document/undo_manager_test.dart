import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

/// A document with a pinned peer id, so merged results are deterministic.
CRDTDocument _doc(String peerId) => CRDTDocument(peerId: PeerId.parse(peerId));

const _peerA = '37f1ec87-6ea5-430b-a627-a6b92b56a02d';
const _peerB = '45ee6b65-b393-40b7-9755-8b66dc7d0518';

void main() {
  group('CRDTUndoManager', () {
    group('tracking', () {
      // A stack that keeps nothing would make every undo do nothing, and say
      // nothing about why, so it is refused where the caller can see it.
      test('refuses a stack limit that keeps no step', () {
        final doc = _doc(_peerA);

        expect(
          () => CRDTUndoManager(doc, stackLimit: 0),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => CRDTUndoManager(doc, stackLimit: -1),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('refuses a handler that cannot invert its operations', () {
        final doc = _doc(_peerA);
        final text = CRDTTextHandler(doc, 'text');
        final undo = CRDTUndoManager(doc);

        expect(text.invertible, isFalse);
        expect(() => undo.track(text), throwsUnsupportedError);
      });

      test('refuses a handler another manager already tracks', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        CRDTUndoManager(doc).track(map);

        expect(() => CRDTUndoManager(doc).track(map), throwsStateError);
      });

      test('refuses a handler of another document', () {
        final doc = _doc(_peerA);
        final other = _doc(_peerB);
        final map = CRDTMapHandler<String>(other, 'map');

        expect(() => CRDTUndoManager(doc).track(map), throwsArgumentError);
      });

      test('records nothing for an untracked handler', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc);

        map.set('a', '1');

        expect(undo.canUndo, isFalse);
      });

      test('untrack stops the recording but keeps the steps', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
          ..track(map);

        map.set('a', '1');
        undo.untrack(map);
        map.set('b', '2');

        expect(undo.canUndo, isTrue);
        undo.undo();
        expect(map.value, {'b': '2'});
        expect(undo.canUndo, isFalse);
      });

      test('untrack keeps following the identities an undo rebuilds', () {
        final doc = _doc(_peerA);
        final set = CRDTORSetHandler<String>(doc, 'set');
        final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
          ..track(set);

        set
          ..add('a')
          ..remove('a');
        undo
          ..untrack(set)

          // The value comes back under a new tag. The step that takes the `add`
          // back names the old one, so it only lands if the link was recorded —
          // which happens while the inverse is built, not while it is stacked.
          ..undo();
        expect(set.value, {'a'});
        undo.undo();
        expect(set.value, <String>{});
      });
    });

    group('map', () {
      test('undoes a set of a new key by removing it', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc)..track(map);

        map.set('a', '1');
        expect(undo.canUndo, isTrue);

        undo.undo();
        expect(map.value, <String, String>{});
        expect(undo.canRedo, isTrue);

        undo.redo();
        expect(map.value, {'a': '1'});
      });

      test('undoes a set over a key by putting the old value back', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map')..set('a', '1');
        final undo = CRDTUndoManager(doc)..track(map);

        map.set('a', '2');
        undo.undo();

        expect(map.value, {'a': '1'});
      });

      test('undoes a delete by putting the entry back', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map')..set('a', '1');
        final undo = CRDTUndoManager(doc)..track(map);

        map.delete('a');
        expect(map.value, <String, String>{});

        undo.undo();
        expect(map.value, {'a': '1'});
      });

      test('undoes an update, and records nothing for a missing key', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map')..set('a', '1');
        final undo = CRDTUndoManager(doc)..track(map);

        map.update('missing', 'x');
        expect(undo.canUndo, isFalse);

        map.update('a', '2');
        undo.undo();
        expect(map.value, {'a': '1'});
      });
    });

    group('register', () {
      test('undoes a set by writing the previous value', () {
        final doc = _doc(_peerA);
        final register = CRDTRegisterHandler<String>(doc, 'reg')..set('one');
        final undo = CRDTUndoManager(doc)..track(register);

        register.set('two');
        expect(register.value, 'two');

        undo.undo();
        expect(register.value, 'one');

        undo.redo();
        expect(register.value, 'two');
      });

      test('cannot take back the first write: there is no unset', () {
        final doc = _doc(_peerA);
        final register = CRDTRegisterHandler<String>(doc, 'reg');
        final undo = CRDTUndoManager(doc)..track(register);

        register.set('one');

        expect(undo.canUndo, isFalse);
        expect(register.value, 'one');
      });
    });

    group('steps', () {
      test('a transaction is one step, whatever it holds', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
          ..track(map);

        doc.runInTransaction(() {
          map
            ..set('a', '1')
            ..set('b', '2')
            ..set('c', '3');
        });

        undo.undo();
        expect(map.value, <String, String>{});
        expect(undo.canUndo, isFalse);
      });

      test('one step per write when the capture timeout is zero', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
          ..track(map);

        map
          ..set('a', '1')
          ..set('b', '2');

        undo.undo();
        expect(map.value, {'a': '1'});
        undo.undo();
        expect(map.value, <String, String>{});
      });

      test('writes close together merge into one step', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(
          doc,
          captureTimeout: const Duration(seconds: 30),
        )..track(map);

        map
          ..set('a', '1')
          ..set('b', '2')
          ..set('c', '3');

        undo.undo();
        expect(map.value, <String, String>{});
        expect(undo.canUndo, isFalse);
      });

      test('stopCapturing ends the step', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(
          doc,
          captureTimeout: const Duration(seconds: 30),
        )..track(map);

        map.set('a', '1');
        undo
          ..stopCapturing()
          ..noop();
        map.set('b', '2');

        undo.undo();
        expect(map.value, {'a': '1'});
      });

      test('a new write drops the redo stack', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
          ..track(map);

        map.set('a', '1');
        undo.undo();
        expect(undo.canRedo, isTrue);

        map.set('b', '2');
        expect(undo.canRedo, isFalse);
      });

      test('a merged step stops growing, so the limit can reach it', () {
        final doc = _doc(_peerA);
        final text = CRDTFugueTextHandler(doc, 'text');
        // Long enough that nothing closes a step on its own: only the cap on
        // how much one step swallows can.
        final undo =
            CRDTUndoManager(doc, captureTimeout: const Duration(days: 1))
              ..track(text);

        for (var i = 0; i < 1030; i++) {
          text.insert(text.length, 'x');
        }

        undo.undo();
        expect(
          text.length,
          lessThan(1030),
          reason: 'one step did not swallow the whole burst',
        );
        expect(text.length, greaterThan(0));
      });

      test('the stack drops its oldest step past the limit', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(
          doc,
          captureTimeout: Duration.zero,
          stackLimit: 2,
        )..track(map);

        map
          ..set('a', '1')
          ..set('b', '2')
          ..set('c', '3');

        undo
          ..undo()
          ..undo();
        expect(undo.canUndo, isFalse);
        // The step that put 'a' in was dropped, so 'a' stays.
        expect(map.value, {'a': '1'});
      });

      test('redo replays the steps in order', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
          ..track(map);

        map
          ..set('a', '1')
          ..set('b', '2');

        undo
          ..undo()
          ..undo();
        expect(map.value, <String, String>{});

        undo.redo();
        expect(map.value, {'a': '1'});
        undo.redo();
        expect(map.value, {'a': '1', 'b': '2'});
        expect(undo.canRedo, isFalse);
      });
    });

    group('origin', () {
      test('records only the tracked origins when they are given', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final mine = Object();
        final undo = CRDTUndoManager(
          doc,
          trackedOrigins: {mine},
          captureTimeout: Duration.zero,
        )..track(map);

        doc.runInTransaction(() => map.set('a', '1'), origin: Object());
        expect(undo.canUndo, isFalse);

        map.set('b', '2');
        expect(undo.canUndo, isFalse);

        doc.runInTransaction(() => map.set('c', '3'), origin: mine);
        expect(undo.canUndo, isTrue);

        undo.undo();
        expect(map.value, {'a': '1', 'b': '2'});
      });

      test('records every local write when no origin is given', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
          ..track(map);

        doc.runInTransaction(() => map.set('a', '1'), origin: Object());
        map.set('b', '2');

        undo
          ..undo()
          ..undo();
        expect(map.value, <String, String>{});
      });

      test('an undo is tagged with the manager', () async {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc)..track(map);

        map
          ..set('a', '1')
          // Warm the cache: a handler with no cached state answers a write
          // with a reset, not a delta.
          ..value;

        final origins = <Object?>[];
        final subscription = map.watch().listen((update) {
          if (update is HandlerDelta<MapDelta<String, String>>) {
            origins.add(update.origin);
          }
        });
        await Future<void>.delayed(Duration.zero);

        undo.undo();
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();

        expect(origins, [same(undo)]);
      });
    });

    group('remote work', () {
      test('a remote change is never on the stack', () {
        final local = _doc(_peerA);
        final remote = _doc(_peerB);
        final localMap = CRDTMapHandler<String>(local, 'map');
        CRDTMapHandler<String>(remote, 'map').set('a', '1');

        final undo = CRDTUndoManager(local)..track(localMap);
        local.importChanges(remote.exportChanges());

        expect(localMap.value, {'a': '1'});
        expect(undo.canUndo, isFalse);
      });

      test('an undo takes back only this peer, and the two converge', () {
        final a = _doc(_peerA);
        final b = _doc(_peerB);
        final mapA = CRDTMapHandler<String>(a, 'map');
        final mapB = CRDTMapHandler<String>(b, 'map');
        final undo = CRDTUndoManager(a)..track(mapA);

        mapA.set('a', 'from-a');
        mapB.set('b', 'from-b');

        a.importChanges(b.exportChanges());
        b.importChanges(a.exportChanges());
        expect(mapA.value, {'a': 'from-a', 'b': 'from-b'});

        undo.undo();
        b.importChanges(a.exportChanges());

        expect(mapA.value, {'b': 'from-b'});
        expect(mapB.value, mapA.value);
      });
    });

    group('lifecycle', () {
      test('changes fires when a stack moves', () async {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
          ..track(map);

        var fired = 0;
        final subscription = undo.changes.listen((_) => fired++);
        await Future<void>.delayed(Duration.zero);

        map.set('a', '1');
        await Future<void>.delayed(Duration.zero);
        expect(fired, greaterThan(0));

        await subscription.cancel();
      });

      // The deltas of an undo go out at the commit that ends it, while the
      // manager is still inside `undo()`. A listener writing back from there
      // must not be taken for part of the step being rebuilt: that would put a
      // second entry on the redo stack, and one undo would need two redos.
      test('a write from inside the undo flush is not part of the step',
          () async {
        final doc = _doc(_peerA);
        final text = CRDTFugueTextHandler(doc, 'text');
        final log = CRDTFugueTextHandler(doc, 'log');
        final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
          ..track(text)
          ..track(log);

        // Warm the cache: a handler that has none answers a write with a
        // reset, not a delta.
        text.value;
        var writeBack = false;
        final subscription = text.watch().listen((_) {
          if (writeBack) {
            writeBack = false;
            log.insert(0, '!');
          }
        });
        // The opening reset is one microtask late; the stream is synchronous
        // from there on.
        await Future<void>.delayed(Duration.zero);

        text.insert(0, 'hello');
        expect(undo.canUndo, isTrue);

        writeBack = true;
        undo.undo();
        expect(text.value, '');
        expect(log.value, '!', reason: 'the listener did write');

        undo.redo();
        expect(text.value, 'hello');
        expect(undo.canRedo, isFalse, reason: 'the step was one redo, not two');

        await subscription.cancel();
      });

      test('importing a snapshot drops both stacks', () {
        final source = _doc(_peerB);
        CRDTMapHandler<String>(source, 'map').set('seed', '0');
        final snapshot = source.takeSnapshot();

        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc)..track(map);

        map.set('a', '1');
        expect(undo.canUndo, isTrue);

        doc.importSnapshot(snapshot);
        expect(undo.canUndo, isFalse);
        expect(undo.canRedo, isFalse);
      });

      test('pruning the history drops both stacks', () {
        final doc = _doc(_peerA);
        final text = CRDTFugueTextHandler(doc, 'text');
        final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
          ..track(text);

        text
          ..insert(0, 'AA-mid-ZZ')
          ..delete(2, 5);
        undo.undo();
        expect(undo.canRedo, isTrue);

        doc
          ..takeSnapshot()
          ..garbageCollect(doc.getVersionVector());
        expect(doc.exportChanges(), isEmpty, reason: 'the history is pruned');

        expect(undo.canUndo, isFalse);
        expect(undo.canRedo, isFalse);
      });

      test('a snapshot that keeps the history keeps the stack', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc)..track(map);

        map.set('a', '1');
        doc.takeSnapshot(pruneHistory: false);

        expect(undo.canUndo, isTrue);
        undo.undo();
        expect(map.value, <String, String>{});
      });

      test('taking a local snapshot prunes, so it drops the stack', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc)..track(map);

        map.set('a', '1');
        doc.takeSnapshot();

        expect(undo.canUndo, isFalse);
      });

      // An OR handler reads a pruned element from the snapshot, which carries
      // no tags. The inverse names the tag the `add` wrote, so it would apply
      // and move nothing: the step has to be gone, not merely useless.
      test('an OR-Set step does not survive the prune that unanchors it', () {
        final doc = _doc(_peerA);
        final set = CRDTORSetHandler<String>(doc, 'set');
        final undo = CRDTUndoManager(doc)..track(set);

        set.add('x');
        doc.takeSnapshot();

        expect(undo.canUndo, isFalse);
        expect(set.value, {'x'});
      });

      test('an OR-Map step does not survive the prune that unanchors it', () {
        final doc = _doc(_peerA);
        final map = CRDTORMapHandler<String, String>(doc, 'map');
        final undo = CRDTUndoManager(doc)..track(map);

        map.put('k', 'v');
        doc.takeSnapshot();

        expect(undo.canUndo, isFalse);
        expect(map.value, {'k': 'v'});
      });

      test('clear drops both stacks', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
          ..track(map);

        map.set('a', '1');
        undo
          ..undo()
          ..clear();

        expect(undo.canUndo, isFalse);
        expect(undo.canRedo, isFalse);
      });

      test('undo and redo refuse to run inside a transaction', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
          ..track(map);

        map.set('a', '1');

        // An undo is a transaction of its own. Nested, its commit would be
        // deferred to the outer one and the step would land on the wrong
        // stack.
        expect(
          () => doc.runInTransaction(undo.undo),
          throwsStateError,
        );
        expect(map.value, {'a': '1'});
        expect(undo.canUndo, isTrue);

        undo.undo();
        expect(
          () => doc.runInTransaction(undo.redo),
          throwsStateError,
        );
      });

      test('a disposed manager records nothing and refuses to undo', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc)..track(map);

        map.set('a', '1');
        undo.dispose();

        map.set('b', '2');
        expect(undo.canUndo, isFalse);
        expect(undo.undo, throwsStateError);
        // Not a stream that could never fire again.
        expect(() => undo.changes, throwsStateError);
      });

      test('disposing the document disposes its managers', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc)..track(map);

        map.set('a', '1');
        expect(undo.canUndo, isTrue);

        doc.dispose();

        expect(undo.canUndo, isFalse);
        expect(undo.undo, throwsStateError);
      });

      test('toString names what each stack holds', () {
        final doc = _doc(_peerA);
        final map = CRDTMapHandler<String>(doc, 'map');
        final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
          ..track(map);

        map
          ..set('a', '1')
          ..set('b', '2');
        undo.undo();

        expect(
          undo.toString(),
          'CRDTUndoManager(undo: 1, redo: 1, handlers: 1)',
        );
      });

      test('two managers on one document keep their own stacks', () {
        final doc = _doc(_peerA);
        final one = CRDTMapHandler<String>(doc, 'one');
        final two = CRDTMapHandler<String>(doc, 'two');
        final undoOne = CRDTUndoManager(doc)..track(one);
        final undoTwo = CRDTUndoManager(doc)..track(two);

        one.set('a', '1');
        expect(undoOne.canUndo, isTrue);
        expect(undoTwo.canUndo, isFalse);

        two.set('b', '2');
        expect(undoTwo.canUndo, isTrue);

        undoTwo.undo();
        expect(two.value, <String, String>{});
        expect(one.value, {'a': '1'});
      });
    });
  });
}

extension on CRDTUndoManager {
  /// Reads a getter so a cascade after [stopCapturing] stays a statement.
  void noop() => canUndo;
}
