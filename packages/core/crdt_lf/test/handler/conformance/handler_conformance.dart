import 'dart:async';
import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

const _id = 'conformance';

// Pinned and ascending: the peer id breaks replay ties, so a random one would
// merge concurrent edits in a different order on every run.
final _peers = [
  PeerId.parse('00000000-0000-4000-8000-00000000000a'),
  PeerId.parse('00000000-0000-4000-8000-00000000000b'),
  PeerId.parse('00000000-0000-4000-8000-00000000000c'),
  PeerId.parse('00000000-0000-4000-8000-00000000000d'),
];

/// Lets the delta stream deliver the events it holds.
Future<void> _pump() => Future<void>.delayed(Duration.zero);

/// Imports into [to] what [from] has and [to] does not.
int _pull(CRDTDocument to, CRDTDocument from) => to.importChanges(
      from.exportChanges(fromVersionVector: to.getVersionVector()),
    );

/// Checks the handler kind [spec] builds against the contract every handler
/// keeps: its cache, convergence, snapshots, transactions, time travel, and,
/// when the handler has them, deltas and undo.
///
/// Call it from the handler's own test file, then add only the cases that are
/// specific to its data model:
///
/// ```dart
/// runHandlerConformanceTests(
///   spec: CRDTRegisterHandler.spec<String>('CRDTRegisterHandler<String>'),
///   read: (register) => register.value,
///   edit: (register, random, token) => register.set(token),
/// );
/// ```
///
/// [read] returns a value the suite can keep and compare with `==` later: a
/// copy of a mutable collection.
///
/// [edit] makes one random operation, chosen with `random`. Every call must
/// change what [read] returns: undo pairs each call with one step on its
/// stack. `token` is unique per peer and per call, so it is a safe value to
/// write: two concurrent writes never pick the same one by chance.
///
/// The delta group runs when the handler is a [DeltaProvider], the undo group
/// when it is [Handler.invertible]. [steps] is the length of a random walk.
void runHandlerConformanceTests<H extends Handler<dynamic>, V>({
  required HandlerSpec<H> spec,
  required V Function(H handler) read,
  required void Function(H handler, Random random, String token) edit,
  int steps = 80,
  int seed = 42,
}) {
  CRDTDocument document([int peer = 0]) => CRDTDocument(peerId: _peers[peer]);

  H open(BaseCRDTDocument doc) => doc.handler(spec, _id);

  /// Runs [count] edits on [handler], each with a token of its own.
  void walk(H handler, Random random, int count, String prefix) {
    for (var step = 0; step < count; step++) {
      edit(handler, random, '$prefix$step');
    }
  }

  /// Three peers editing at once, with partial syncs in between.
  List<CRDTDocument> concurrentPeers(Random random) {
    final docs = [document(), document(1), document(2)];
    final handlers = docs.map(open).toList();
    for (final handler in handlers) {
      read(handler);
    }
    for (var round = 0; round < steps ~/ 4; round++) {
      for (var peer = 0; peer < docs.length; peer++) {
        edit(handlers[peer], random, 'p${peer}r$round');
      }
      final to = random.nextInt(docs.length);
      final from = (to + 1 + random.nextInt(docs.length - 1)) % docs.length;
      _pull(docs[to], docs[from]);
    }
    return docs;
  }

  /// Reopens peer 0 in a new session every round, from what [reload] keeps
  /// of the session before, while a second peer edits next to it.
  void expectReloadConverges(
    CRDTDocument Function(CRDTDocument session) reload,
  ) {
    final random = Random(seed);
    var session = document();
    walk(open(session), random, steps ~/ 4, 'before');
    final other = document(1);
    final otherHandler = open(other);
    _pull(other, session);

    // A reload every round: a single one rarely prunes the highest id spent.
    for (var round = 0; round < steps ~/ 2; round++) {
      session = reload(session);
      final handler = open(session);
      edit(handler, random, 'r$round');
      edit(otherHandler, random, 'o$round');
      _pull(other, session);
      _pull(session, other);

      expect(read(handler), read(otherHandler), reason: 'round $round');
    }
  }

  group('${spec.type} conformance', () {
    group('cache', () {
      test('the folded value equals a value computed from scratch', () {
        final handler = open(document());
        final random = Random(seed);
        for (var step = 0; step < steps; step++) {
          read(handler);
          edit(handler, random, 's$step');
        }

        final folded = read(handler);
        handler.invalidateCache();

        expect(read(handler), folded);
      });

      test('a peer folding remote changes reads what a replay reads', () {
        final source = document();
        final sourceHandler = open(source);
        final folding = document(1);
        final foldingHandler = open(folding);
        final replaying = document(2);
        final replayingHandler = open(replaying)
          ..useIncrementalCacheUpdate = false;
        read(foldingHandler);
        read(replayingHandler);

        final random = Random(seed);
        for (var step = 0; step < steps; step++) {
          edit(sourceHandler, random, 's$step');
          _pull(folding, source);
          _pull(replaying, source);
          // Read now and then, so the queue also holds several changes.
          if (step % 5 == 4) {
            expect(
              read(foldingHandler),
              read(replayingHandler),
              reason: 'step $step',
            );
          }
        }

        final value = read(sourceHandler);
        expect(read(foldingHandler), value);
        expect(read(replayingHandler), value);
        foldingHandler.invalidateCache();
        expect(read(foldingHandler), value);
      });
    });

    group('convergence', () {
      test('two peers syncing every round agree with a replay', () {
        final a = document();
        final aHandler = open(a);
        final b = document(1);
        final bHandler = open(b);
        final replay = document(2);
        final replayHandler = open(replay)..useIncrementalCacheUpdate = false;
        read(aHandler);
        read(bHandler);
        read(replayHandler);
        // Only an order-independent state keeps its cache when a change from
        // the past arrives; any other one replays.
        final keepsCache = aHandler.stateIsOrderIndependent;

        final random = Random(seed);
        for (var round = 0; round < steps ~/ 2; round++) {
          edit(aHandler, random, 'a$round');
          edit(bHandler, random, 'b$round');
          _pull(a, b);
          _pull(b, a);
          _pull(replay, a);

          if (keepsCache) {
            // Before reading: a read rebuilds the cache it would hide.
            expect(aHandler.cachedState, isNotNull, reason: 'round $round');
            expect(bHandler.cachedState, isNotNull, reason: 'round $round');
          }
          final replayed = read(replayHandler);
          expect(read(aHandler), replayed, reason: 'round $round, peer a');
          expect(read(bHandler), replayed, reason: 'round $round, peer b');
        }
      });

      test('edits after a reload from the history converge with another peer',
          () {
        expectReloadConverges(
          (session) => document()..importChanges(session.exportChanges()),
        );
      });
    });

    group('arrival order', () {
      test('every causal arrival order gives the same value', () {
        final random = Random(seed);
        final docs = concurrentPeers(random);
        final reference = document(3);
        for (final doc in docs) {
          _pull(reference, doc);
        }
        final changes = reference.exportChanges();
        final expected = read(open(reference));

        for (var order = 0; order < 4; order++) {
          final doc = document(3);
          final handler = open(doc);
          read(handler);
          for (final change in _causalShuffle(changes, random)) {
            doc.applyChange(change);
            read(handler);
          }
          expect(read(handler), expected, reason: 'order $order');
        }
      });
    });

    group('snapshot', () {
      test('an empty handler survives a snapshot', () {
        final source = document();
        final empty = read(open(source));

        final restored = document(1)..importSnapshot(source.takeSnapshot());

        expect(read(open(restored)), empty);
      });

      test('a snapshot restores the value on a fresh peer', () {
        final source = document();
        final sourceHandler = open(source);
        walk(sourceHandler, Random(seed), steps, 's');
        final value = read(sourceHandler);
        final snapshot = source.takeSnapshot(pruneHistory: false);

        final openedAfter = document(1)..importSnapshot(snapshot);
        expect(read(open(openedAfter)), value, reason: 'opened after import');

        final openedBefore = document(2);
        final handler = open(openedBefore);
        read(handler);
        openedBefore.importSnapshot(snapshot);
        expect(read(handler), value, reason: 'opened before import');
      });

      test('a snapshot plus the changes after it reads as the history', () {
        final source = document();
        final sourceHandler = open(source);
        final replay = document(1);
        final replayHandler = open(replay)..useIncrementalCacheUpdate = false;
        final random = Random(seed);

        walk(sourceHandler, random, steps ~/ 2, 'before');
        _pull(replay, source);
        final snapshot = source.takeSnapshot();
        walk(sourceHandler, random, steps ~/ 2, 'after');
        _pull(replay, source);

        final restored = document(2)
          ..importSnapshot(snapshot)
          ..importChanges(source.exportChanges());

        final value = read(replayHandler);
        expect(read(sourceHandler), value, reason: 'the pruned source');
        expect(read(open(restored)), value, reason: 'the restored peer');
      });

      test('edits after a reload converge with a full-history peer', () {
        expectReloadConverges(
          (session) => document()..importSnapshot(session.takeSnapshot()),
        );
      });

      test('a snapshot taken right after an import holds what it imported', () {
        final source = document();
        final sourceHandler = open(source);
        final target = document(1);
        final handler = open(target);
        final random = Random(seed);

        walk(sourceHandler, random, steps ~/ 2, 'before');
        _pull(target, source);
        read(handler);
        // Left queued: nothing reads the handler before the snapshot.
        walk(sourceHandler, random, steps ~/ 2, 'after');
        _pull(target, source);

        final restored = document(2)..importSnapshot(target.takeSnapshot());

        expect(read(open(restored)), read(sourceHandler));
      });

      test('a peer that is behind merges a snapshot to its value', () {
        final random = Random(seed);
        final source = document();
        final sourceHandler = open(source);
        final behind = document(1);
        final handler = open(behind);

        walk(sourceHandler, random, steps ~/ 2, 'early');
        _pull(behind, source);
        read(handler);
        walk(sourceHandler, random, steps ~/ 2, 'late');
        final value = read(sourceHandler);

        behind.mergeSnapshot(source.takeSnapshot(pruneHistory: false));

        expect(read(handler), value);
      });
    });

    group('transaction', () {
      test('a walk in transactions leaves the value of the same walk', () {
        final stepByStep = open(document());
        walk(stepByStep, Random(seed), steps, 's');
        final expected = read(stepByStep);

        final source = document(1);
        final grouped = open(source);
        final random = Random(seed);
        for (var batch = 0; batch < 4; batch++) {
          source.runInTransaction(() {
            for (var step = batch * steps ~/ 4;
                step < (batch + 1) * steps ~/ 4;
                step++) {
              edit(grouped, random, 's$step');
            }
          });
        }
        expect(read(grouped), expected, reason: 'the folded value');
        grouped.invalidateCache();
        expect(read(grouped), expected, reason: 'the compacted changes');

        final remote = document(2);
        final handler = open(remote);
        remote.importChanges(source.exportChanges());
        expect(read(handler), expected, reason: 'a remote peer');
      });
    });

    group('time travel', () {
      test('each cursor reads the value recorded after that change', () {
        final doc = document();
        final handler = open(doc);
        final random = Random(seed);
        final recorded = <int, V>{0: read(handler)};
        for (var step = 0; step < steps ~/ 2; step++) {
          edit(handler, random, 's$step');
          recorded[doc.exportChanges().length] = read(handler);
        }

        final session = doc.toTimeTravel();
        addTearDown(session.dispose);
        final past = session.getHandler<H, dynamic>(open);
        for (final MapEntry(key: cursor, value: value) in recorded.entries) {
          session.jump(cursor);
          expect(read(past), value, reason: 'cursor $cursor');
        }
      });
    });

    if (open(document()) is DeltaProvider<dynamic, ComposableDelta<dynamic>>) {
      group('deltas', () {
        test('the deltas of a local walk rebuild the value', () async {
          final handler = open(document());
          read(handler);
          final projection = _Projection(handler);
          await _pump();

          final random = Random(seed);
          for (var step = 0; step < steps; step++) {
            edit(handler, random, 's$step');
            projection.expectInStep('step $step');
          }
          await projection.dispose();
        });

        test('the deltas of remote changes rebuild the value', () async {
          final source = document();
          final sourceHandler = open(source);
          final target = document(1);
          final handler = open(target);
          read(handler);
          final projection = _Projection(handler);
          await _pump();

          final random = Random(seed);
          for (var step = 0; step < steps; step++) {
            edit(sourceHandler, random, 's$step');
            // One change at a time, then a batch of several.
            if (step < steps ~/ 2 || step == steps - 1) {
              _pull(target, source);
              projection.expectInStep('step $step');
            }
          }
          await projection.dispose();
        });

        test('the deltas of two peers editing at once rebuild each value',
            () async {
          final a = document();
          final aHandler = open(a);
          final b = document(1);
          final bHandler = open(b);
          read(aHandler);
          read(bHandler);
          final aProjection = _Projection(aHandler);
          final bProjection = _Projection(bHandler);
          await _pump();

          final random = Random(seed);
          for (var round = 0; round < steps ~/ 2; round++) {
            edit(aHandler, random, 'a$round');
            edit(bHandler, random, 'b$round');
            _pull(a, b);
            _pull(b, a);
            aProjection.expectInStep('round $round, peer a');
            bProjection.expectInStep('round $round, peer b');
          }
          await aProjection.dispose();
          await bProjection.dispose();
        });
      });
    }

    if (open(document()).invertible) {
      group('undo', () {
        test('undo walks back every step, redo walks forward again', () {
          final doc = document();
          final handler = open(doc);
          final random = Random(seed);
          // A first step outside the stack: some handlers cannot undo back to
          // an empty value (a register has no way to clear itself).
          edit(handler, random, 'seed');

          final undo = CRDTUndoManager(
            doc,
            captureTimeout: Duration.zero,
            stackLimit: steps + 1,
          )..track(handler);
          addTearDown(undo.dispose);

          final states = <V>[read(handler)];
          for (var step = 0; step < steps; step++) {
            edit(handler, random, 's$step');
            states.add(read(handler));
          }

          for (var i = states.length - 1; i > 0; i--) {
            expect(read(handler), states[i], reason: 'before undo to $i');
            expect(undo.canUndo, isTrue, reason: 'the stack is short at $i');
            undo.undo();
          }
          expect(read(handler), states.first);
          expect(undo.canUndo, isFalse, reason: 'the stack is long');

          for (var i = 1; i < states.length; i++) {
            expect(undo.canRedo, isTrue, reason: 'no redo for $i');
            undo.redo();
            expect(read(handler), states[i], reason: 'after redo to $i');
          }
          expect(undo.canRedo, isFalse);
        });
      });
    }
  });
}

/// [changes] in a random order that still delivers every change after its
/// dependencies.
List<Change> _causalShuffle(List<Change> changes, Random random) {
  final pending = [...changes];
  final delivered = <OperationId>{};
  final ids = {for (final change in changes) change.id};
  final order = <Change>[];
  while (pending.isNotEmpty) {
    final ready = pending
        .where(
          (change) => change.deps
              .every((dep) => delivered.contains(dep) || !ids.contains(dep)),
        )
        .toList();
    final next = ready[random.nextInt(ready.length)];
    pending.remove(next);
    delivered.add(next.id);
    order.add(next);
  }
  return order;
}

/// A copy of a handler's value kept only from `readSynced()` and the deltas
/// that follow it.
class _Projection {
  _Projection(Handler<dynamic> handler)
      : _provider =
            handler as DeltaProvider<dynamic, ComposableDelta<dynamic>> {
    _subscription = _provider.watch().listen(_onUpdate);
  }

  final DeltaProvider<dynamic, ComposableDelta<dynamic>> _provider;
  late final StreamSubscription<HandlerUpdate<dynamic>> _subscription;
  final List<HandlerUpdate<dynamic>> events = [];

  Object? _value;
  int _seq = -1;

  void _onUpdate(HandlerUpdate<dynamic> update) {
    events.add(update);
    switch (update) {
      case HandlerReset<dynamic>():
        final point = _provider.readSynced();
        _value = point.value;
        _seq = point.seq;
      case HandlerDelta<dynamic>(:final seq, :final delta):
        if (seq <= _seq) {
          return;
        }
        _value =
            _provider.applyDelta(_value, delta as ComposableDelta<dynamic>);
        _seq = seq;
    }
  }

  void expectInStep(String reason) {
    expect(_value, _provider.value, reason: reason);
  }

  Future<void> dispose() => _subscription.cancel();
}
