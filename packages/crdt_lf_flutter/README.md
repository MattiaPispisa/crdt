# CRDT LF Flutter

Flutter reactivity for [`crdt_lf`](https://pub.dev/packages/crdt_lf): rebuild your
widgets when CRDT state changes — at the **document** level or scoped to a single
**handler**, with selectors and a collaborative text field.

Built on top of [`provider`](https://pub.dev/packages/provider) — so you also get
`context.read` / `context.watch` / `context.select` for a `CRDTDocument` for free
(`provider` is re-exported minimally).

- [CRDT LF Flutter](#crdt-lf-flutter)
  - [Features](#features)
  - [How it works](#how-it-works)
  - [Getting Started](#getting-started)
  - [Usage](#usage)
    - [Provide a document](#provide-a-document)
    - [Document-level rebuilds](#document-level-rebuilds)
    - [Handler-scoped rebuilds](#handler-scoped-rebuilds)
    - [Imperative access](#imperative-access)
    - [Collaborative text](#collaborative-text)
    - [Presence cursors](#presence-cursors)

## Features

- **`CrdtProvider`** — provide a `CRDTDocument` to the subtree, created and owned
  by the provider (`CrdtProvider(create:)`) or caller-owned
  (`CrdtProvider.value(value:)`). Wraps `provider`'s `InheritedProvider`.
- **`CrdtBuilder`** / **`CrdtSelector<R>`** — rebuild on every document update, or
  only when a selected slice changes.
- **`CrdtHandlerBuilder<H>`** / **`CrdtHandlerSelector<H, R>`** — rebuild only when
  a **specific handler** changes (optionally including nested handlers).
- **`CrdtHandlerListener<H>`** — side-effect callback on a handler change.
- **`CrdtTextFieldBuilder`** — a `TextEditingController` bound to a text
  handler, the way collaborative editor bindings work.
- **`CrdtTextCursorsOverlay`** — paints collaborators' carets/selections
  over the text field, anchored by stable positions.
- **`CrdtAwarenessCursorsOverlay`** — overlays collaborators' mouse-style
  presence cursors (pointer arrow + name bubble) on any pane.
- Context helpers: `context.crdtDocument`, `context.watchCrdtDocument()`,
  `context.selectCrdtDocument(...)`, `context.crdtHandler<H>(id)`.

## Getting Started

```yaml
dependencies:
  crdt_lf_flutter: 
  crdt_lf: 
```

## Usage

### Provide a document

```dart
// Owning mode: the provider creates the document lazily and disposes it.
CrdtProvider(
  create: (_) => CRDTDocument(),
  child: const MyApp(),
);

// Value mode: you own the document lifecycle.
CrdtProvider.value(value: doc, child: const MyApp());
```

### Document-level rebuilds

```dart
// Rebuild on any change.
CrdtBuilder(
  builder: (context, document) => Text(textHandler.value),
);

// Rebuild only when a derived slice changes.
CrdtSelector<int>(
  selector: (context, document) => listHandler.value.length,
  builder: (context, count) => Text('$count todos'),
);
```

### Handler-scoped rebuilds

Rebuild only when one handler changes — unrelated handlers don't trigger a
rebuild. `CrdtHandlerBuilder` hands you the concrete typed handler (the base
`Handler` exposes no `value`), which is also the right tool for list/map handlers
whose value is mutated in place (a value `Selector` wouldn't detect the change).

```dart
CrdtHandlerBuilder<CRDTListHandler<String>>(
  id: 'todos',
  builder: (context, handler) => Text('${handler.value.length}'),
);

// Derived slice from a handler.
CrdtHandlerSelector<CRDTListHandler<String>, int>(
  id: 'todos',
  selector: (context, handler) => handler.value.length,
  builder: (context, count) => Text('$count'),
);

// Also rebuild when a nested/descendant handler changes.
CrdtHandlerBuilder<CRDTMapRefHandler>(
  id: 'root',
  nested: true,
  builder: (context, handler) => ...,
);

// Side effects only (no rebuild).
CrdtHandlerListener<CRDTListHandler<String>>(
  id: 'todos',
  listener: (context, handler) => showSnackBar(...),
  child: ...,
);
```

### Imperative access

For actions (insert/delete/change) you don't need reactivity — read the handler
once:

```dart
context.crdtHandler<CRDTListHandler<String>>('todos').insert(0, 'new');
```

### Collaborative text

`CrdtTextFieldBuilder` binds a `TextEditingController` to the text handler
(`CRDTTextHandler` or `CRDTFugueTextHandler`) registered under `id`, the way
collaborative editor bindings do:

- **local edits** are pushed into the handler immediately as the precise delta
  of each editing gesture (prefix/suffix trimming, one transaction per
  gesture — no full-text diff, no debounce);
- **IME composition** (CJK input, autocorrect) is respected: nothing is
  committed while a composing region is active;
- **remote changes** are adopted into the controller in place, with the caret
  and selection kept anchored: with a `CRDTFugueTextHandler` through **stable
  positions** (`stablePositionAt` — anchors tied to element identity, exact
  even for multi-region remote changes), otherwise mapped through the remote
  delta;
- the subtree **never rebuilds** — `builder` runs once and the controller is
  updated directly.

```dart
CrdtTextFieldBuilder(
  id: 'note',
  builder: (context, controller) => TextField(controller: controller),
);
```

The delta primitives are exported too (`TextDelta`, `computeTextDelta`,
`mapOffsetThroughDelta`) if you need to build a custom binding.

#### Remote text cursors

Publish the local selection with `onSelectionAnchorsChanged` (the anchors are
serializable — send them over your presence channel, e.g. the awareness
plugin of `crdt_socket_sync`) and draw collaborators with
`CrdtTextCursorsOverlay`. Anchors are reported only while the field has
focus — on blur the callback fires once with `null`s, so with several bound
fields a peer shows at most one cursor, where they are typing:

```dart
CrdtTextFieldBuilder(
  id: 'note',
  onSelectionAnchorsChanged: (base, extent) => publishPresence(base, extent),
  builder: (context, controller) => CrdtTextCursorsOverlay(
    id: 'note',
    cursors: remoteTextCursors, // List<CrdtTextCursor> from presence
    child: TextField(controller: controller),
  ),
);
```

### Presence cursors

`CrdtAwarenessCursorsOverlay` draws collaborators' **mouse pointers** (arrow
plus name bubble) over any pane — the presence complement of the in-field
text cursors above. It is transport-agnostic: you map your presence channel
to `CrdtAwarenessCursor`s (positions normalized into `[0, 1]`, so cursors
map across window sizes) and publish what `onLocalPointer` reports:

```dart
CrdtAwarenessCursorsOverlay(
  cursors: remotePointers, // List<CrdtAwarenessCursor> from presence
  onLocalPointer: (position, {required hovering}) =>
      publishPresence(position, hovering),
  child: pane,
);
```

## (deep dive) How it works

`crdt_lf` exposes a `CRDTDocument.updates` broadcast stream that fires on any
local edit, applied remote change or snapshot import. `CrdtProvider` exposes the
document through `provider` and bridges `updates` so
provider dependents (`context.watch` / `context.select`, and the widgets above)
rebuild automatically.

Handler-scoped widgets rebuild only when a per-handler signal changes: the O(1)
`CRDTDocument.revisionForHandler(id)`, a monotonic revision that grows on every
applied change targeting the handler (local or imported) and on snapshot
imports carrying its state. With `nested: true` the ids and revisions of the
handler and its descendants (`ContainerHandler.childRefs`) are folded into one
hash, so structural changes (a child added or removed) are detected too.