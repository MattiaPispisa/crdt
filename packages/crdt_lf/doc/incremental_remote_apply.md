# Incremental apply for remote changes

Status: **implemented**.

A remote change used to invalidate the target handler's cache, so the next read
replayed the whole history. It now advances the cached state instead. Two
independent rules allow it, and a change takes the incremental path when either
one holds:

1. **The state commutes** under causal delivery — the order the changes are
   folded in does not matter. The Fugue sequence handlers and the OR handlers.
2. **The change extends the replay order** — it is newer than everything already
   folded in. This one holds for *every* handler.

This document explains why each rule is safe, and how they are built.

## The cost it removes

A remote change reaches `_foldOrDropCachesForChange`
(`document.dart`), which calls `_refreshHandlerCaches`. Before this work that
call invalidated every handler the change targets, and the next read went
through `cachedOrComputedState()` → `computeState()`, which seeds from the
snapshot and replays every operation in the history — `O(history)` per remote
change.

Measured with `benchmark/src/benchmarks/remote_apply_benchmark.dart` (import one
remote change, then read the value). "Before" is the same benchmark file run on
the commit that precedes this work, on the same machine.

| Handler | Size | Before | After |
|---|---|---|---|
| `CRDTFugueTextHandler` | 2 000 chars | 0.91 ms | 0.06 ms |
| `CRDTFugueTextHandler` | 10 000 chars | 5.54 ms | 0.20 ms |
| `CRDTFugueTextHandler` | 30 000 chars | 19.6 ms | 0.69 ms |
| `CRDTTextHandler` | 2 000 chars | 96 µs | 9 µs |
| `CRDTTextHandler` | 30 000 chars | 417 µs | 13 µs |
| `CRDTMapHandler` | 1 000 keys | 0.66 ms | 11 µs |
| `CRDTMapHandler` | 5 000 keys | 3.04 ms | 5 µs |

The rows above import a change that arrives **in order**. The OR handlers gain
nothing there — rule 2 already covered it — so their rows import a change from
the past instead, the case rule 1 is for:

| Handler | Size | Before | After |
|---|---|---|---|
| `CRDTORSetHandler` | 1 000 values | 1.00 ms | 30 µs |
| `CRDTORSetHandler` | 5 000 values | 4.33 ms | 114 µs |
| `CRDTORMapHandler` | 1 000 keys | 1.29 ms | 68 µs |
| `CRDTORMapHandler` | 5 000 keys | 5.87 ms | 0.25 ms |

In a live editing session every remote keystroke pays this, so it matters long
before the internals of any one handler do. The map is the sharpest case because
its history holds one change per key, so the replay it avoids is the longest.

What is left for the Fugue text still grows a little with the document, but it
is no longer the replay: it is the projection, `values()` plus building the
`String`, which runs on every read of a dirty state.

Local operations already had this: `registerOperation` calls
`_internalIncrementCachedState`, which patches the cached state in place.

## Why the full replay existed

`computeState()` replays operations sorted by `(HLC, author)`. The sort is what
makes every peer agree, so the obvious worry is that applying a remote change on
top of the current state — in arrival order rather than sorted order — produces
a different result.

## Rule 1: the state commutes

### The Fugue tree

For the Fugue tree the order does not matter. **The tree is commutative under
causal delivery.** Verified with a randomized test: 3 simulated peers, 10 rounds of
random inserts / deletes / updates with random pairwise syncing, then the whole
operation set replayed on fresh trees in 12 different causal orders. 60 seeds,
720 replays, all identical.

The reason is that nothing in the tree depends on *when* an operation arrives:

- `insert` resolves `leftOrigin` / `rightOrigin` against nodes that already
  exist, because causal readiness guarantees the changes that created them are
  applied first.
- `_isAncestorOf(x, y)` is stable once both nodes exist: the tree only grows,
  and a node's parent and side never change, so `y` cannot become a descendant
  of `x` later.
- Same-side siblings are kept sorted by element id, so their order does not
  depend on insertion order.
- `delete` and `update` address nodes by id and are idempotent.

### The OR handlers

`CRDTORSetHandler` and `CRDTORMapHandler` commute for a different reason: they
already carry their own clock. Every `add` / `put` mints an `ORHandlerTag`
(peer id + HLC) that travels **inside the operation**, and the state answers
from the tags, not from the position of a write in the history — a value is
present because it has a live tag, and the value of an OR-map key is the live
entry with the highest tag. The rest only grows: the seen tags, the tombstones.
An add checks the tombstones already collected, a remove tomb-stones tags that
causal readiness guarantees are already there, and both an add and a remove drop
the same key from the snapshot-only seed.

Verified the same way as the tree: 3 peers, 30 rounds with random pairwise
syncing, the operation set replayed in 12 random causal orders, 60 seeds. 1 440
replays per handler, all identical, and every folded state equal to the replayed
one.

### Who opts in

Commutativity is a property of the handler, not of the framework. It is opt-in
through `CacheableStateProvider.stateIsOrderIndependent`, which defaults to
`false`. It is on for `FugueSequenceHandler` (so `CRDTFugueTextHandler` and
`CRDTFugueListHandler`), `CRDTORSetHandler` and `CRDTORMapHandler`.

It stays off for:

- `CRDTTextHandler` and `CRDTListHandler` — their operations carry positions, so
  the replay order is what places them.
- `CRDTRegisterHandler` and `CRDTMapHandler` — they are last-write-wins on
  *replay order*, not on a clock. `register/handler.dart` says so directly:
  "Only local writes reach the incremental path, and a local write is the latest
  in clock order, so it wins." Making these commutative means keeping a clock per
  key in the state, plus a tombstone per deleted key so an older insert cannot
  bring it back, plus a second stamp for the conditional `update` of the map. It
  is separate work, and rule 2 already carries them through the common case.
- `CRDTFugueMovableListHandler` — its LWW is keyed on `positionHlc` /
  `valueHlc`, which is almost enough, but `HybridLogicalClock.compareTo` only
  compares `(l, c)`. When two concurrent `move` (or `update`) operations on the
  same element carry the exact same HLC, neither `happenedAfter` the other, so
  the winner is whichever is applied first. The sorted replay breaks that tie the
  same way on every peer; arrival order does not. Opting it in means comparing
  `(hlc, author)`: the author is in the change header, so the operation format
  stays as it is, but the element would have to remember it and the **snapshot**
  format — today `positionHlc` and `valueHlc`, 8 bytes each — would have to carry
  it too.

## Rule 2: the change extends the replay order

`computeState()` is a left fold over `changesForHandler(...).sorted()`. For any
fold, adding an element that lands **last** is the same as folding it on top of
the result:

```
fold(sorted(S ∪ {c})) == applyOperation(fold(sorted(S)), c)   when c > max(S)
```

This says nothing about the handler, so it holds for all of them. Every built-in
`incrementCachedState` is "apply this operation to the state", which is exactly
the step of the fold — and the precondition "`c` is the newest" is what makes
the ones above correct. The library already leaned on it for local writes: a
local change carries a clock newer than everything applied (`_changeFromOp`
ticks the clock), which is why the register handler can say "a local write is
the latest in clock order, so it wins".

The order is `(hlc, author)`, exposed as `compareChangeOrder` in `change.dart`
and shared with `ChangeList.sorted` so the two can never drift apart. The
comparison stays zero-decode: `Change.hlc` and `Change.author` live in the
change header, not in the operation payload.

### Where it gives up

The condition fails exactly when two peers type at the same time: B receives a
change A produced before seeing B's last edits, so it sorts before something B
already folded in. That change forces a recompute. This is why rule 2 does not
replace rule 1 — for the handlers that opt in, rule 1 keeps working through
concurrent editing, while rule 2 carries every other handler through the common
case of one writer at a time (or none, for a viewer).

Setting `useIncrementalCacheUpdate = false` on a handler turns off both rules, so
there is still one switch that disables every incremental path.

## How it works

### The apply path stays zero-decode

The document's apply path deliberately never decodes operation envelopes:
handler routing uses `_isAffectedByChange`, a cached binary prefix compare. A
per-change decode measured **+12%** on the Apply benchmark, so decoding an
operation eagerly to apply it is not acceptable.

So the raw change is **queued** and applied lazily at read time. The apply path
only appends a `Change` to a per-handler list, which needs the handler id and
nothing else. The decode happens on the next read — the moment the value is
actually wanted — and costs `O(pending)` instead of `O(history)`.

The batch path already decoded envelopes: `_foldOrDropCachesForChanges`
calls `OperationEnvelopeCodec.decode(...).handlerId` per change, and now groups
the batch by handler id instead of collecting a set of ids. It is the
single-change path that stays prefix-compare only.

### The pieces

1. **`CacheableStateProvider` owns the queue.** `_pendingRemoteChanges` sits next
   to `_cachedState`, with two hooks: `stateIsOrderIndependent` (above) and the
   private `_operationFromChange`, which `Handler` implements with its
   `operationFactory`.
2. **`_refreshHandlerCaches` routes instead of always invalidating.** Its
   callback answers, per handler: `null` for untouched (cached version advanced,
   as before), a non-empty list of the changes that target it, or an empty list
   for "touched, invalidate outright". A handler that gets changes has its
   revision bumped either way, so `revisionForHandler` still moves and the
   Flutter binding still rebuilds.
3. **`_queueRemoteChanges` takes all the changes or none.** It refuses when the
   handler holds no state to advance, when the queue would grow past the cap, or
   when neither rule holds — the caller then invalidates.
4. **The replay boundary tracks rule 2.** `_replayBoundary` is the newest change
   folded into the state or waiting in the queue. It is set from three places:
   `Handler.operations()` reports the last change of the set a recompute replays
   (the list is already sorted), the document reports every local change once it
   is created in `_transactionFlushWork`, and `_queueRemoteChanges` keeps it at
   the maximum of what it accepts. Between registering a local operation and
   committing it the boundary is unknown, because the change that carries it does
   not exist yet — rule 2 stays closed for that window.
5. **Reading `cachedState` drains the queue.** Every handler already reads the
   state through that getter, so none of them can forget to drain.
   `_internalIncrementCachedState` drains too, so a local operation never lands
   on a state that still has remote changes waiting.
6. **Anything that fails falls back to a full recompute.** A change that does not
   decode, or an operation that throws while being applied, drops the cache — the
   same failure policy the local incremental path already used.

### The cap

`_maxPendingRemoteChanges` is 256. Draining costs one decode plus one apply per
queued change, while a full recompute costs one per change in the history: past
some ratio the recompute is cheaper. The cap also bounds the memory a handler
nobody reads can hold on to.

### What still invalidates

Snapshot import, snapshot merge and history pruning replace the base the replay
starts from. They keep invalidating everything through `_invalidateHandlers()`,
and `invalidateCache()` clears the queue as well.

`useIncrementalCacheUpdate = false` also turns off the drain, not only the
queueing: a handler can be switched off while changes are already waiting, and
folding them in would call the very `incrementCachedState` the flag rejects.
The queue is dropped instead and the next read replays.

## Verification

- **Differential oracle** (`test/handler/incremental_oracle_test.dart`, group
  *remote incremental cache oracle*): one document advances its cache from the
  imported changes while another, with `useIncrementalCacheUpdate = false`,
  replays the history on every read. They must never disagree. Runs over every
  built-in handler, and covers both the batch path (`importChanges`) and the
  single-change path (`applyChange`).
- **Concurrent editing** (same file, `_concurrentOracle`): two peers edit and
  exchange changes both ways against a third peer that never folds anything, so
  each side receives changes that sort before what it already folded in. Both
  peers are compared to the replaying one on every round. The peer ids are
  pinned, because they are the tie-break of the replay order and random ones
  would interleave the peers differently on every run. A handler that opts into
  rule 1 also has to keep its cache through all of it, checked **before** every
  read — a read would rebuild it and hide an import that dropped it. Runs for
  the Fugue text, the OR-set and the OR-map with the cache check, and for the
  replay-order handlers without it.
- **Framework behaviour** (`test/document/providers_test.dart`, groups *remote
  changes and the handler cache* and *the replay boundary*): the cache survives a
  queued change and an in-order one, a change from the past drops it and the
  recompute gives the sorted result, a Fugue handler takes that same change
  anyway, the revision still advances, a batch bigger than the cap falls back, a
  change that cannot be decoded or applied falls back, the queue takes exactly
  `_maxPendingRemoteChanges` changes and no more, turning
  `useIncrementalCacheUpdate` off drops a queue that is already waiting, a change
  from the past is folded onto a pruned history (the boundary is then "no change
  at all"), and a change imported in the middle of a transaction drops a
  replay-order cache while a commutative one keeps it.
- A snapshot taken right after an import, with no read in between, contains the
  imported changes (`test/handler/fugue_text/handler_test.dart`, and
  `providers_test.dart` for a queue that is still waiting when the snapshot asks
  for the state).

## Relation to run compression

This is orthogonal to run compression and the two compose. Run compression
lowers the constant of a replay and the memory per element; this removes the
replay from the remote path altogether.
