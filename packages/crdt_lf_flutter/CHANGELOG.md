## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_flutter-v0.1.0/packages/crdt_lf_flutter)

**Date:** 2026-07-15

### Added

- Initial release of `crdt_lf_flutter`, a Flutter reactivity layer for `crdt_lf`
  built on top of [`provider`](https://pub.dev/packages/provider) (re-exported),
  the same way `flutter_bloc` is:
  - `CrdtProvider` — dependency injection of a `CRDTDocument`, created and owned
    by the provider (`CrdtProvider(create:)`) or caller-owned
    (`CrdtProvider.value(value:)`). Wraps `provider`'s `InheritedProvider` and
    bridges `CRDTDocument.updates` so `context.watch` / `context.select` rebuild
    on change; composes inside a `MultiProvider`.
  - `CrdtBuilder` — `builder: (context, document)`, rebuilds on every document
    update.
  - `CrdtSelector<R>` — `selector: (context, document) => R`, rebuilds only when
    the selected value changes.
  - `CrdtHandlerBuilder<H>` — `id` + `builder: (context, handler)`, rebuilds only
    when that handler changes (an applied change, a snapshot import, or — with
    `nested: true` — a descendant handler). Hands you the concrete typed handler
    to read its `value`.
  - `CrdtHandlerSelector<H, R>` — `id` + `selector: (context, handler) => R`,
    rebuilds only when the selected value changes.
  - `CrdtHandlerListener<H>` — fires a side-effect callback on a handler change
    (BlocListener analogue).
  - `CrdtTextFieldBuilder` — keeps a `TextEditingController` synced to a
    collaborative text value (reconciling concurrent remote edits, caret
    best-effort) and exposes it to a `builder`.
  - Context helpers: `context.crdtDocument`, `context.watchCrdtDocument()`,
    `context.selectCrdtDocument(...)`, and `context.crdtHandler<H>(id)` for
    imperative access.
  - Requires `crdt_lf ^3.4.0` for the O(1) `revisionForHandler` signal used by
    the handler-scoped widgets.
