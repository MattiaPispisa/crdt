# Handler deltas

Status: **implemented**.

A consumer of a handler used to learn *that* something changed
(`CRDTDocument.updates`, `revisionForHandler`) and had to re-read the whole
value to learn *what*. A handler now also publishes a stream of **deltas**: one
event per `Change`, describing how its observable state moved. A consumer can
keep its own projection without ever reading `handler.value`.

```dart
final text = CRDTFugueTextHandler(doc, 'text');

var mine = '';
var seen = -1;

text.watch().listen((update) {
  switch (update) {
    case HandlerReset():
      // The base moved: read it, and remember which events it already holds.
      final point = text.readSynced();
      mine = point.value;
      seen = point.seq;
    case HandlerDelta():
      if (update.seq <= seen) {
        return; // already inside the value the last read handed over
      }
      mine = update.delta.applyToText(mine);
      seen = update.seq;
  }
});
```

This is not **delta-state CRDT** replication. Nothing here reaches the wire:
a delta is a local observation, like `Y.Event.delta` in Yjs or
`LoroEventBatch` in Loro.

## The four vocabularies

By shape, not by handler.

| Delta | Handlers |
|---|---|
| `SequenceDelta<T>` — `SeqRetain`, `SeqInsert`, `SeqDelete`, `SeqMove` | `CRDTTextHandler`, `CRDTListHandler`, `CRDTFugueTextHandler`, `CRDTFugueListHandler`, `CRDTFugueMovableListHandler`, the container lists |
| `MapDelta<K, V>` — one `MapEntrySet` or `MapEntryRemoved` per touched key | `CRDTMapHandler`, `CRDTORMapHandler`, `CRDTMapRefHandler` |
| `SetDelta<T>` — `added` and `removed` | `CRDTORSetHandler` |
| `RegisterDelta<T>` — `previous` and `current` | `CRDTRegisterHandler` |

`SequenceDelta` is the Quill/Yjs shape on purpose: it is what an editor
binding already knows how to consume. Text handlers use
`SequenceDelta<String>` where one element is one **rune**, matching the way
they index their text.

`SeqMove` exists only for `CRDTFugueMovableListHandler`. A delete plus an
insert would describe the same result, but it would throw away the element
identity that handler exists to preserve — a list view would rebuild the row
instead of animating it. A delta that holds a move holds nothing else, and it
supports neither `compose` nor `mapOffset`.

## Reading is one operation

A reset does **not** carry the value. Carrying it would force a recompute at
the moment the event is built, which is exactly the cost the lazy design
avoids. But a consumer that reads the value later, from its listener, would
read a value that may already hold deltas it is about to receive, and it would
apply them twice.

So `readSynced()` returns the value **and** the point of the stream it
reflects:

> On a `HandlerReset`, call `readSynced()`, adopt `value`, remember `seq`, and
> discard every `HandlerDelta` whose `seq` is less than or equal to it.

The recompute therefore happens in the consumer, on the consumer's schedule,
or never if the consumer went away.

## What it costs

A handler nobody reads normally costs nothing: a remote change is queued and
folded in at the next read (see `incremental_remote_apply.md`). A **watched**
handler cannot wait for a read that may never come, so it folds the change
when it **arrives**. The work is the same; only the moment changes.

While nobody watches, the whole thing is one `null` check on the apply path:
the sink is `null` and no event is built. That is asserted by
`test/document/delta_provider_test.dart`, group *cost when nobody watches*.

Measured with `benchmarks/src/benchmarks/delta_emission_benchmark.dart`, which
runs every row twice. One remote keystroke plus the read that follows it:

| Handler | Size | Unwatched | Watched |
|---|---|---|---|
| `CRDTFugueTextHandler` | 2 000 chars | 42.8 µs | 34.5 µs |
| `CRDTFugueTextHandler` | 10 000 chars | 104 µs | 88 µs |
| `CRDTTextHandler` | 2 000 chars | 9.8 µs | 11.4 µs |
| `CRDTTextHandler` | 10 000 chars | 12.8 µs | 18.6 µs |
| `CRDTMapHandler` | 5 000 keys | 4.7 µs | 5.1 µs |
| `CRDTFugueMovableListHandler` | 1 000 elements | 53 µs | 71 µs |
| `CRDTFugueMovableListHandler` | 5 000 elements | 186 µs | 355 µs |

The Fugue text rows do not get slower, because the work only moves: a watched
handler folds the change on arrival and the read that follows finds the state
ready. Typing 2 000 characters locally into a Fugue text goes from 56.4 ms to
72.5 ms, about 8 µs of event per keystroke.

The movable list is the one handler that does get slower, and by an amount
that grows with the list — see its shape below.

The `CRDTTextHandler` rows type at the **end** of the text, which is the case
that has to count the runes again because the index clamped. An edit in the
middle costs nothing extra.

Small benchmarks swing about ±10% between runs, so re-run before calling
anything a regression. The shapes behind the numbers:

- **`CRDTFugueTextHandler`** — one `O(√n)` positional query per operation, not
  per character: an insert chain is contiguous, so the place of the first
  element is the place of all of them. A delete pays one query per element,
  read before the elements become tombstones.
- **`CRDTTextHandler`** — the delta is built from the same offsets the new
  state is built from. An edit in the middle of the text costs nothing extra;
  an edit that clamps (typing at the very end) pays one rune walk.
- **`CRDTMapHandler`, the OR handlers, `CRDTRegisterHandler`** — one lookup
  before the write and one after, `O(1)`.
- **`CRDTFugueMovableListHandler`** — one walk of the visible order per
  operation, on top of the one a read pays anyway. Its visible order is a
  projection of the tree *through* the identity map, so nothing the tree
  reports describes it, and a move only looks like a move when you compare the
  order either side of the apply. This is the one handler whose watched cost
  grows with the size of the value; the walk is shared with the read, and the
  two orders are held by reference rather than copied, but it cannot be turned
  into the `O(√n)` query the other sequence handlers use.

## Semantics worth knowing before you rely on them

1. **One event per change, in fold order.** Not one per transaction. A
   transaction whose operations do not compound produces several changes and
   therefore several events. A consumer that wants the Yjs-style
   one-event-per-transaction shape composes them itself: `compose` is public.

2. **Fold order is not replay order.** For a handler whose state commutes
   (the Fugue handlers, the OR handlers) a change that sorts *before* what the
   state already holds is still folded in arrival order. The state converges;
   **the sequence of deltas two peers observe can differ**. The stream
   describes the local trajectory of one view, not a replicated log. Yjs has
   the same property. Anything that hashes or persists a value derived from
   the delta sequence has to tolerate it.

3. **A reset is not an error.** It is the honest answer when the base the
   replay starts from was replaced. `ResetCause` says which case it was:

   | cause | when |
   |---|---|
   | `initial` | the first event of every subscription, so the reset path is exercised on the first frame |
   | `cacheDropped` | the cached state went, so there is nothing left to move |
   | `applyFailed` | an operation could not be decoded, or threw |
   | `snapshotImport` / `snapshotMerge` | a snapshot replaced the base |
   | `deltasMissed` | a read folded the queue in before the eager drain did; the state is right, the deltas that described that step are gone |

4. **A handler that resolves by replay order resets under concurrency.**
   `CRDTTextHandler`, `CRDTListHandler`, `CRDTMapHandler` and
   `CRDTRegisterHandler` are not `stateIsOrderIndependent`. When two peers
   write at the same time, a change arrives that sorts before what the handler
   already folded in, the cache goes, and the consumer gets `cacheDropped`
   instead of a delta. That recompute was already the price of reading
   `handler.value` in that situation — the delta stream does not add it, it
   only makes it visible. Pick a Fugue handler for text and lists that several
   peers edit at once.

5. **The sink is purely observational.** It never influences the state. An
   operation that mutates the state in place and then refuses it (see
   `CacheableStateProvider.incrementCachedState`) has whatever it reported
   thrown away whole, and the consumer gets a reset instead of a delta that
   describes a state nobody holds.

6. **Only what anyone can see is reported.** An `add` of a value already in an
   OR-set moves the internal tags but not the set, an `update` of a key that
   is not in a map does nothing, an insert past the end appends and a delete
   past the end is a no-op. Every one of those produces an **empty** delta, not
   a phantom entry. The delta always describes the *clamped* effect, because it
   is derived from the same values the new state is built from.

## Verification

- **Delta oracle** (`test/handler/delta_oracle_test.dart`): a consumer that
  keeps its projection **only** from `readSynced()` plus deltas must equal
  `handler.value` after every step. It runs for every built-in handler, over
  randomized edit streams, across the batch path (`importChanges`), the
  single-change path (`applyChange`) and the local path, and for two peers
  editing at the same time with pinned peer ids.
- **The compaction invariant** (same file, group *the compaction invariant*):
  the composition of the deltas of the operations a transaction fused must
  equal the delta the peer that receives the compacted change observes.
  Checked over contiguous inserts, insert-then-partial-delete, forward and
  backward delete runs, and same-index updates.
- **Clamping** (same file): inserts past the end, deletes past the end,
  updates on missing keys, OR-set adds of already-live values.
- **Framework behaviour** (`test/document/delta_provider_test.dart`): a change
  waits for a read while nobody watches and is folded at arrival while someone
  does, cancelling the last watcher goes back to waiting, the sequence number
  only grows, `readSynced` reports the point its value reflects, and disposing
  the document ends the stream.
- **Composition** (`test/delta/*_test.dart`): `compose(a, b).apply(base)` must
  equal `b.apply(a.apply(base))`, over randomized deltas, for all four
  vocabularies.
