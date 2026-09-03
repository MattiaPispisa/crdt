## Unreleased

**Date:** --

### Added

- **Undo and redo**, from the toolbar or with ⌘Z / ⌘⇧Z (Ctrl on Windows and
  Linux). An undo takes back what *you* wrote and leaves what everyone else
  wrote in place. A burst of typing is one undo, not one per character.

- **A room now survives a reload without a connection.** Each room is kept in
  the browser's storage as it changes, and read back when you open it — so
  reloading offline, or on a relay that has forgotten the room, brings your
  text back instead of an empty page. Writing is delayed a quarter of a second
  so typing never waits on the disk.

## 0.9.0

**Date:** 2026-08-29

### Changed

- Thanks to the new versions of `crdt_lf` (v`4.1.0`) and `crdt_lf_flutter` (v.`0.5.0`), which introduce “run” and “delta,” the editor is faster and uses less memory

## 0.8.0

**Date:** 2026-08-22

### Changed

- Update `crdt_lf` to `4.0.0`
- Update `crdt_lf_flutter` to `0.4.0`
- Update `crdt_socket_sync` to `0.7.0` 

## 0.7.0

**Date:** 2026-08-02

### Added

- Export the document as Markdown, HTML or PDF, from the room toolbar. The
  PDF embeds its fonts, so accented text survives; images come out as their
  alt text and emoji are not drawn.
- **Line numbers** — a numbered gutter beside the source.
- **Word wrap** — turn it off and long lines run as far as they need to, with the editor scrolling sideways and following the caret.

### Changed

- Update `crdt_lf` to `3.5.0` 

## 0.6.0

**Date:** 2026-08-02

### Changed

- Update `crdt_lf` to `3.4.3` 

## 0.5.0

**Date:** 2026-07-30

### Added

- Appearance (light/dark/system)
- User settings are preserved (username, color, appearance)
- Improved Home accessibility
- Keyboard shortcut for the most used formatting actions — bold, italic, inline
  code and link.
- Splash screen during app bootstrap.
- The credit line links to the author's site.

### Changed

- Update `crdt_lf_flutter` to `0.3.0` 

## 0.4.0

**Date:** 2026-07-26

### Added

- View the app changelog from the About page.

## 0.3.0

**Date:** 2026-07-26

### Changed

- Sync now runs on the `crdt_socket_sync` relay

## 0.2.0

**Date:** 2026-07-21

[101](https://github.com/MattiaPispisa/crdt/issues/101)

### Added

- Keyboard shortcuts for the markdown editor.
- Placeholder text in the editor.
- Settings, including a licenses page.
- Syntax highlighting

## 0.1.0

Initial release: real-time collaborative markdown editor built on `crdt_lf`.
