## [0.1.0](https://github.com/MattiaPispisa/crdt/tree/crdt_lf_quill-v0.1.0/packages/adapters/text/crdt_lf_quill)

**Date:** --

### Added

- `CrdtQuillBinder` binds a flutter_quill `QuillController` to a `CRDTFugueRichTextHandler`.
  Needs `crdt_lf` 5.3.0 and `crdt_lf_flutter` 0.7.0.
  [209](https://github.com/MattiaPispisa/crdt/issues/209)
- Exported converters between Quill deltas and `RichTextDelta`, to build your own binding.
- Peer changes stay out of the controller's undo stack, like `History(userOnly: true)`.
- The binder refuses embeds (images, videos) and reports them through `onUnsupported`.
- `debugVerifyCrdtQuillProjection` switches the full projection check, in debug and release.
