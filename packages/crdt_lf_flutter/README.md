# CRDT LF Flutter

Flutter reactivity for [`crdt_lf`](https://pub.dev/packages/crdt_lf): rebuild your
widgets when CRDT state changes — at the **document** level or scoped to a single
**handler**, with selectors and a collaborative text field.

Built on top of [`provider`](https://pub.dev/packages/provider), the same way
[`flutter_bloc`](https://pub.dev/packages/flutter_bloc) is — so you also get
`context.read` / `context.watch` / `context.select` for a `CRDTDocument` for free
(`provider` is re-exported).

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

## Features

- **`CrdtProvider`** — provide a `CRDTDocument` to the subtree, created and owned
  by the provider (`CrdtProvider(create:)`) or caller-owned
  (`CrdtProvider.value(value:)`). Wraps `provider`'s `InheritedProvider`.
- **`CrdtBuilder`** / **`CrdtSelector<R>`** — rebuild on every document update, or
  only when a selected slice changes.
- **`CrdtHandlerBuilder<H>`** / **`CrdtHandlerSelector<H, R>`** — rebuild only when
  a **specific handler** changes (optionally including nested handlers).
- **`CrdtHandlerListener<H>`** — side-effect callback on a handler change.
- **`CrdtTextFieldBuilder`** — a `TextEditingController` kept in sync with a
  collaborative text value.
- Context helpers: `context.crdtDocument`, `context.watchCrdtDocument()`,
  `context.selectCrdtDocument(...)`, `context.crdtHandler<H>(id)`.

## How it works

`crdt_lf` exposes a `CRDTDocument.updates` broadcast stream that fires on any
local edit, applied remote change or snapshot import. `CrdtProvider` exposes the
document through `provider` and bridges `updates` (via `startListening`), so
provider dependents (`context.watch` / `context.select`, and the widgets above)
rebuild automatically.

Handler-scoped widgets rebuild only when a per-handler signal changes: the O(1)
`CRDTDocument.revisionForHandler(id)`, a monotonic revision that grows on every
applied change targeting the handler (local or imported) and on snapshot
imports carrying its state. With `nested: true` the revisions of the handler
and its descendants (`ContainerHandler.childRefs`) are summed.

## Getting Started

```yaml
dependencies:
  crdt_lf_flutter: ^0.1.0
  crdt_lf: ^3.4.0
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

```dart
CrdtHandlerSelector<CRDTFugueTextHandler, String>(
  id: 'note',
  selector: (context, handler) => handler.value,
  builder: (context, text) => CrdtTextFieldBuilder(
    value: text,
    builder: (context, controller) => TextField(
      controller: controller,
      onChanged: (next) => doc.runInTransaction(
        () => context.crdtHandler<CRDTFugueTextHandler>('note').change(next),
      ),
    ),
  ),
);
```
