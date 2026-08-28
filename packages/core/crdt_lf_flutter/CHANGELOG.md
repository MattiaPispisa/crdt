## [Unreleased]

**Date:** 2026-08-26

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf_flutter-v0.4.0...crdt_lf_flutter-v0.5.0)

### Added

- `CrdtHandlerDeltaListener` reports **what** each change did to a handler, one call per change,
  so a widget can move a projection it already holds instead of re-reading the value. It performs
  the read a reset asks for and drops the events that read already covers, so a delta is never
  applied twice. Like `CrdtHandlerListener`, it renders its child unchanged and never rebuilds the
  subtree. [132](https://github.com/MattiaPispisa/crdt/issues/132)

### Changed

- Requires `crdt_lf` 4.1.0, for the handler delta streams.
- `CrdtTextFieldBuilder` keeps its text by **moving it with the deltas** the handler reports,
  instead of projecting the whole document again after every edit. A keystroke used to rebuild the
  entire string; now it costs the size of the edit. On a 50 000-character Fugue document a keystroke
  goes **773 µs → 162 µs** and taking in a remote one goes **704 µs → 62 µs**; at 10 000 characters,
  134 → 57 µs and 116 → 35 µs. Typing is now nearly flat in the size of the document.
  `CRDTTextHandler` is the one row that pays instead of gains — 44 → 54 µs — because its value is
  already a plain cached string, so building a delta buys it nothing. Measured with
  `benchmarks/src/benchmarks/text_field_benchmark.dart`; see `benchmarks/results.md`.
  Because the text is derived and never read back, the field checks it against the handler after
  every step and reads once to recover if the two disagree. The check is cheap on purpose: a Fugue
  handler answers its length without projecting anything. Set
  `debugVerifyCrdtTextFieldProjection` to `false` to skip the stricter debug-only version, which
  compares the whole value and therefore costs exactly what the field now avoids.
- `CrdtTextFieldBuilder` takes a batch of remote changes in one at a time rather than composing them
  into a single controller write. Each one now costs the size of its own edit, so there is nothing
  left worth batching, and Flutter folds the writes into one frame anyway.
- `CrdtTextFieldBuilder` places the caret from the delta the handler reports, instead of re-deriving
  the remote edit by diffing the old and new text. A diff collapses a change that touched two
  regions into one span covering the caret, which dragged it to the end of that span; the reported
  delta says exactly what moved. Stable positions still come first for `CRDTFugueTextHandler` — they
  follow element identity — so this is what `CRDTTextHandler`, which has none, gains.
- `CrdtTextFieldBuilder` no longer loses a remote change that was published but not yet delivered
  when a keystroke lands in that window. It asks the stream how far it has got, and settles with one
  read when it is behind, instead of pushing the edit against a text the handler no longer holds.
- `CrdtTextFieldBuilder` keeps a pending IME composition across a remote change, instead of dropping
  what the user was in the middle of typing.
- `CrdtTextFieldBuilder` re-subscribes when its `id` changes, instead of staying bound to the
  handler it started with.
- `CrdtTextCursorsOverlay` counts caret offsets in the text the field is painting
  (`RenderEditable.plainText`, already materialised) instead of asking the handler, which projected
  the whole document on every resolve. It also re-subscribes when its `id` changes.
- `CrdtTextFieldBuilder` reads the value once when it mounts rather than twice: seeding the field
  and answering the reset that opens the stream are the same question, and on a large document the
  answer is a projection of the whole text.

## [0.4.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_flutter-v0.4.0/packages/crdt_lf_flutter)

**Date:** 2026-08-16

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf_flutter-v0.3.0...crdt_lf_flutter-v0.4.0)

### Changed

- Requires `crdt_lf` 4.0.0, where text is indexed by code point rather than by code unit. [106](https://github.com/MattiaPispisa/crdt/issues/106)

### Fixed

- `CrdtTextCursorsOverlay`: a remote cursor anchored past an emoji (or any
  non-BMP character) now paints at the right position instead of drifting by
  one code unit per preceding astral character. [106](https://github.com/MattiaPispisa/crdt/issues/106)

## [0.3.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_flutter-v0.3.0/packages/crdt_lf_flutter)

**Date:** 2026-08-01

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf_flutter-v0.2.1...crdt_lf_flutter-v0.3.0)

### Added

- `CrdtTextCursorsOverlay` carets now moves to their new position instead of jumping there. [102](https://github.com/MattiaPispisa/crdt/issues/102)

## [0.2.1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_flutter-v0.2.1/packages/crdt_lf_flutter)

**Date:** 2026-07-21

[compare to previous release](https://github.com/MattiaPispisa/crdt/compare/crdt_lf_flutter-v0.2.0+1...crdt_lf_flutter-v0.2.1)

### Fixed

- `CrdtTextFieldBuilder`: an edit made next to an identical character no longer slides to the wrong side of
  that character. The text delta is now anchored to the post-edit caret.

## [0.2.0+1](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_flutter-v0.2.0+1/packages/crdt_lf_flutter)

**Date:** 2026-07-19

- Documentation release: refreshes the CHANGELOG and docs published on pub.dev. No functional changes since `0.2.0`.

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
