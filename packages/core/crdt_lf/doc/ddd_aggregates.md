# Replicating DDD aggregates

This guide is for one shape of app: a domain model made of **aggregates**,
replicated across several installations that edit offline and sync later.
It shows how to map that model on `crdt_lf`, what the merge rules really are,
and where the library stops.

It covers two grains. First the aggregate as one value, which keeps the DDD
consistency boundary. Then a set of `ToDo`, where the merge has to work field
by field. Read the main [README](../README.md) first for the handler list and
the core API.

## The model

Keep the aggregate as **one value**, under its id, in a
`CRDTORMapHandler<String, T>`:

```dart
final doc = CRDTDocument();
final invoices = CRDTORMapHandler<String, Invoice>(
  doc,
  'invoices',
  valueCodec: InvoiceCodec(), // your own; the default is JsonValueCodec
);

invoices.put(invoice.id, invoice);
invoices.remove(invoice.id);
final all = invoices.value; // Map<String, Invoice>
```

One handler per aggregate type. The key is the aggregate id. The value is the
whole aggregate, encoded by a `ValueCodec<T>` you write
(`lib/src/handler/or_map/handler.dart`, the `keyCodec` / `valueCodec`
parameters). Without a codec the handler falls back to `JsonValueCodec`, which
works for maps of plain JSON values.

This keeps the DDD rule intact: **the aggregate is the consistency boundary**.
The handler picks one whole version, and your domain code decides what to do
next. When you need the merge to work field by field instead, see
[Field-level merge](#field-level-merge-a-set-of-todo).

## Merge rules

`CRDTORMapHandler` is an OR-Map (observed-removed). Each `put` writes a new
**tag**; `remove` tombstones the tags it has seen. Here is what that means for
two installations that edit at the same time.

| Concurrent edits | Result |
|---|---|
| `put(k, x)` and `put(k, y)` | one whole version wins: the entry with the highest tag (HLC, then peer id) |
| `put(k, x)` and `remove(k)` | **add-wins**: the key stays, with `x` |
| `remove(k)` and `remove(k)` | the key goes; removes are idempotent |
| `remove(k)`, then `put(k, x)` later | the key comes back; the new tag is not tombstoned |

All four rows are pinned by tests in
`test/handler/or_map/handler_test.dart`: "should handle concurrent puts on
same key (conflict resolution)", "concurrent put/remove converge with add-wins
semantics", "remove only tombstones observed tags", and "should handle remove
followed by put on same key". The winner is picked in `ORMapState._state`.

Two consequences worth saying out loud:

- **Last writer wins per aggregate, not per field.** If installation A edits
  the customer name and installation B edits the due date of the same invoice,
  one of the two edits is gone after the merge. Both are still *valid*
  aggregates — that is the point — but B's work is lost.
- **A delete never beats a concurrent edit.** An aggregate someone else was
  still editing comes back. Model deletion as a state of the aggregate
  (`status: archived`) when you need the delete to be the final word.

## Field-level merge: a set of ToDo

Sometimes the aggregate is too coarse. Take `ToDo(id, displayName, done)`:
one installation renames todo `1`, another ticks it done. With the model
above one of the two edits is lost. If both must survive, the fields need to
be separate CRDTs.

Two ways to do it today.

### Option 1: one handler per field

Each todo is a `CRDTMapRefHandler`, and each field is its own handler. The
root is a `CRDTMapRefHandler` keyed by todo id.

```dart
// One builder per field type, so the tag is written once.
CRDTRegisterHandler<String> newName(BaseCRDTDocument d, String id) =>
    CRDTRegisterHandler<String>(d, id, handlerType: 'todo/name');
CRDTRegisterHandler<bool> newDone(BaseCRDTDocument d, String id) =>
    CRDTRegisterHandler<bool>(d, id, handlerType: 'todo/done');

void registerTodoTypes(CRDTDocument d) {
  // Every kind the tree is made of, so a child received from a peer resolves
  // without being opened here first.
  d
    ..register(newName)
    ..register(newDone)
    ..register(CRDTMapRefHandler.new);
}

// Child ids come from the todo id, not from doc.newHandlerId(). That is why
// the children go in with setRef: child() mints a random id.
CRDTMapRefHandler openTodo(
  CRDTDocument doc,
  CRDTMapRefHandler root,
  String todoId,
) {
  final existing = doc.registeredHandlers['todo/$todoId'];
  if (existing != null) {
    return existing as CRDTMapRefHandler;
  }
  final todo = doc.handler(CRDTMapRefHandler.new, 'todo/$todoId')
    ..setRef('displayName', doc.handler(newName, 'todo/$todoId/displayName'))
    ..setRef('done', doc.handler(newDone, 'todo/$todoId/done'));
  root.setRef(todoId, todo);
  return todo;
}
```

Reading and writing goes through the refs:

```dart
final todo = openTodo(doc, root, '1');
todo.getRefAs<CRDTRegisterHandler<String>>('displayName')!.set('foo');
todo.getRefAs<CRDTRegisterHandler<bool>>('done')!.set(true);

print(root.resolved); // {1: {displayName: foo, done: true}}
```

Now the concurrent rename and the concurrent tick both survive: they are
writes to two different handlers, so they never compete.

Four things this design asks of you:

- **Derive the child ids from the todo id.** With `doc.newHandlerId()`, two
  installations that create todo `1` offline build two different subtrees.
  The root map is last-writer-wins, so one subtree wins whole and the other
  stays in the document forever as a second root (measured: 7 handlers and
  2 roots for one visible todo). With ids derived from the todo id the same
  case merges field by field, and leaves 4 handlers and 1 root.
- **Make "create" idempotent.** Building a handler with an id that is already
  registered throws `CrdtException: Handler with ID todo/1 already
  registered`; `doc.handler(spec, id)` returns the open one instead. The refs
  still have to be written once only, which is what the early return in
  `openTodo` is for.
- **A delete always beats a concurrent field edit.** `root.delete('1')` is a
  write to the root map; a field edit is a write to another handler. They do
  not compete, so the todo goes even when the edit is newer. The library has
  no OR (add-wins) container of references today.
- **Re-adding a deleted id brings the old values back.** The field handlers
  still hold what they held. Write the new values right after the `setRef`,
  or give the new todo a new id.

The payoff of this design is the choice of CRDT per field. `done` is a
`CRDTRegisterHandler<bool>`. A `displayName` that two people type into at the
same time can be a `CRDTFugueTextHandler` instead, and merge per character.

A generic handler is required to name its tag for a reason: the default would be
built from `runtimeType`, and `dart2js` minifies that in a Flutter web release
build. A constant keeps it stable across builds and peers.

### Option 2: flat composite keys

Keep one OR-Map and put the field name in the key.

```dart
final todos =
    CRDTORMapHandler<String, Object?>(doc, 'todos', handlerType: 'todos');

doc.runInTransaction(() {
  todos
    ..put('1/displayName', 'milk')
    ..put('1/done', false);
});

todos.put('1/displayName', 'foo'); // installation A
todos.put('1/done', true);         // installation B, at the same time
// both survive: {1/displayName: foo, 1/done: true}
```

No refs, no nested handlers, nothing to declare. Every field merges on its own,
last-writer-wins. The costs:

- **A delete can leave half a todo.** Deleting means removing every key of
  that todo, in one transaction. The OR-Map is add-wins, so a concurrent edit
  to one field brings **that key** back and nothing else. Measured: after a
  concurrent delete and rename the map holds `{1/displayName: late rename}`,
  with no `done`. Your read model has to treat a todo with missing fields as
  either deleted or defaulted. Decide which, and write it down.
- **Every field is last-writer-wins.** No per-character merge for the title,
  no counter.
- **The key format is your contract.** Pick a separator that todo ids cannot
  contain.

### Which one

| | one handler per field | flat composite keys |
|---|---|---|
| per-field merge | yes | yes |
| CRDT per field (text, counter…) | yes | no, LWW only |
| concurrent create of the same id | merges, with derived ids | merges |
| delete vs concurrent edit | delete wins | partial todo survives |
| setup | builders, refs | none |

Start with the flat keys when the fields are scalars, as `ToDo` is. Move to
one handler per field when a field needs its own CRDT, or when a nested
`resolved` tree is what your UI wants to read.

## Limits

### 1. You cannot see the conflict

When two installations write the same key at the same time, both entries stay
live inside the handler. Only the winner is projected; the loser is dropped in
`ORMapState._state` and there is no API to read it.

So the domain cannot say "these two installations disagreed" from the CRDT
alone. Carry what you need inside the aggregate payload — a version number,
the last editor, a timestamp — and let the domain compare them on the next
read.

### 2. A snapshot drops the tags, and a later delete can be lost

`getSnapshotState` writes the projected map: keys and values, no tags. On
reload the entries come back **tagless** (`ORMapState._snapshotOnly`). A
`remove` of such a key carries no tags, so it is sent as a `removeAll`
(`or_map/operation.dart`, `removeAll: tags.isEmpty`).

The two representations of the same entry — tagged and tagless — do not
answer a `remove` the same way. And `takeSnapshot` does not change the state
already in memory: the handler keeps its tags while the snapshot on disk has
none.
The peer's answer then depends on whether it replayed the history or reloaded
the snapshot. Measured, with peer A deleting a key both peers had:

| A's snapshot | B live | B after restart |
|---|---|---|
| `takeSnapshot()` (prunes) | key **stays** | key gone |
| `takeSnapshot(pruneHistory: false)` | key gone | key **stays** |

**Workaround, verified:** call `invalidateCache()` on the OR handlers right
after `takeSnapshot()`. The next read rebuilds the state from the snapshot, so
memory and disk agree and every case converges on "key gone".

`CRDTORSetHandler` behaves the same way.

### 3. No counter

The library has no additive handler. `PNCounterHandler` is an example of a
custom handler in the README, not something you can import. A quantity inside
an LWW aggregate loses concurrent increments: two installations that each add
one item end up with one added, not two.

If a number must survive concurrent writes, keep it out of the aggregate value
and give it its own handler — see "Custom handlers" in the README.

## What the library already gives you

Do not rebuild these:

- `doc.runInTransaction(...)` — several handlers changed as one atomic step,
  with an `origin` tag you can use to skip your own echo.
- `doc.revisionForHandler(id)` — the reactive signal for "did this handler
  move?".
- `handler.watch()` — a delta per change, when you need to know *what* moved.
- `takeSnapshot` / `garbageCollect` — bounded storage. Read the pruning notes
  in the README first, and see limit 2 above.
- The persistence adapters (`crdt_lf_sqlite`, `crdt_lf_drift`, `crdt_lf_hive`)
  and `crdt_socket_sync` for the transport.

## Scaling: one document, or one per aggregate

`exportChanges` filters by version vector only, not by handler
(`lib/src/document/document.dart`). One document is one DAG. Every
installation gets the history of **every** aggregate, and replays it.

With many aggregates the other option is one `CRDTDocument` per aggregate:
each one syncs and loads on its own, and an installation can hold only the
aggregates it needs. The cost is on you — routing several documents over one
connection, and one persistence entry per document. We have not checked what
`crdt_socket_sync` offers for this, so treat it as an open trade-off, not a
recommendation.
