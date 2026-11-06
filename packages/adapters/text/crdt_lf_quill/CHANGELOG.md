## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_quill-v0.1.0/packages/adapters/text/crdt_lf_quill)

**Date:** --

### Added

- `CrdtQuillBinder` binds a flutter_quill `QuillController` to a `CRDTFugueRichTextHandler`.
  Needs `crdt_lf` 5.3.0 and `crdt_lf_flutter` 0.7.0.
  [209](https://github.com/MattiaPispisa/crdt/issues/209)
- Exported converters between Quill deltas and `RichTextDelta`, to build your own binding.
- Peer changes stay out of the controller's undo stack, like `History(userOnly: true)`.
- `CrdtQuillBinder.undoManager` routes undo and redo through a `CRDTUndoManager`; `crdtQuillOrigin` tags the editor's writes.
- Quill embeds map to handler embeds and back: Quill images and videos are the `crdt_lf` ones
  (`span.image`, `span.video`), and the image resize is the `displayWidth` mark. `embedTypes` picks the
  types the editor writes; an embed of another type, or data or an attribute value the handler refuses,
  goes to `onUnsupported`, and a refusal deletes no embed. See [Embeds](README.md#embeds).
- `crdtQuillEmbedBuilders` adds to the app's embed builders one that shows handler embeds of another shape
  than Quill's, through the builder of their `type` or a fallback.
- `crdtQuillUnknownEmbedBuilder` shows any embed without a builder, so a peer's embed never breaks the editor.
- `debugVerifyCrdtQuillProjection` switches the full projection check, in debug and release.
