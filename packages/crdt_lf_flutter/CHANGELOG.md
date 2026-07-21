## [0.2.1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_flutter-v0.2.1/packages/crdt_lf_flutter)

**Date:** 2026-07-21

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf_flutter-v0.2.0+1...crdt_lf_flutter-v0.2.1)

### Fixed

- `CrdtTextFieldBuilder`: an edit made next to an identical character no longer slides to the wrong side of
  that character. The text delta is now anchored to the post-edit caret.

## [0.2.0+1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_flutter-v0.2.0+1/packages/crdt_lf_flutter)

**Date:** 2026-07-19

Documentation release: refreshes the CHANGELOG and docs published on pub.dev. No functional changes since `0.2.0`.

## [0.2.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_flutter-v0.2.0/packages/crdt_lf_flutter)

**Date:** 2026-07-18

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf_flutter-v0.1.0...crdt_lf_flutter-v0.2.0)

### Added

- Split the presence overlay into three composable, all-exported pieces for
  maximum flexibility:
  - `CrdtAwarenessCursorsBuilder` — the transport/layout half of the overlay
    (positioning + local-pointer handling) with a per-cursor `builder`, so you
    can draw a completely custom marker (an avatar, a badge, …) per cursor.
  - `CrdtAwarenessCursorMarker` — the standalone default marker (pointer arrow
    + name bubble) for a single cursor, positioning-agnostic.
  - `CrdtAwarenessCursorsOverlay` — the ready-made combination of the two.
- `CrdtAwarenessCursorStyle` to style a marker: a plain
  `color` for the common case, or a full style (color + label text style +
  marker sizes) when you need more. Set it per cursor via
  `CrdtAwarenessCursor.style` or for the whole overlay via
  `CrdtAwarenessCursorsOverlay.style` (each peer keeps its own identity color).

## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_flutter-v0.1.0/packages/crdt_lf_flutter)

**Date:** 2026-07-17

### Added

- Initial release of `crdt_lf_flutter` ([94](https://github.com/MattiaPispisa/crdt/issues/94)), a Flutter reactivity layer for `crdt_lf`
  built on top of [`provider`](https://pub.dev/packages/provider) (minimal re-exported):
  - `CrdtProvider` — dependency injection of a `CRDTDocument`, created and owned
    by the provider or caller-owned;
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
  - `CrdtTextFieldBuilder` — binds a `TextEditingController` to the text
    handler registered under `id`.
  - `CrdtTextCursorsOverlay` + `CrdtTextCursor` — paints collaborators'
    carets, selection highlights and name tags over the text field.
  - `CrdtAwarenessCursorsOverlay` + `CrdtAwarenessCursor` — overlays
    collaborators' mouse-style presence cursors (pointer arrow + name
    bubble) on any pane, and reports the local pointer for publishing.
  - Context helpers: `context.crdtDocument`, `context.watchCrdtDocument()`,
    `context.selectCrdtDocument(...)`, and `context.crdtHandler<H>(id)` for
    imperative access.
