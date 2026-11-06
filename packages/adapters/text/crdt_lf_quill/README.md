# CRDT LF Quill

[![package badge][package_badge]][pub_link]
[![pub points][pub_points_badge]][pub_link]
[![pub likes][pub_likes_badge]][pub_link]
[![codecov][codecov_badge]][codecov_link]
[![ci badge][ci_badge]][ci_link]
[![license][license_badge]][license_link]
[![pub publisher][pub_publisher_badge]][pub_publisher_link]

Collaborative rich text for [`flutter_quill`](https://pub.dev/packages/flutter_quill).
`CrdtQuillBinder` keeps a `QuillController` in step with a
`CRDTFugueRichTextHandler` from [`crdt_lf`](https://pub.dev/packages/crdt_lf),
so several peers can edit the same document, with bold, links, headings and
lists.

- [CRDT LF Quill](#crdt-lf-quill)
  - [Usage](#usage)
  - [How it works](#how-it-works)
    - [Units](#units)
    - [Attributes](#attributes)
    - [Embeds](#embeds)
    - [The last newline](#the-last-newline)
    - [Undo](#undo)
    - [Projection check](#projection-check)
    - [Remote cursors](#remote-cursors)
  - [Limits](#limits)
  - [Example](#example)
  - [Apps](#apps)
  - [Packages](#packages)

## Usage

Register a rich text handler on the document, provide the document with
`CrdtProvider` (from [`crdt_lf_flutter`](https://pub.dev/packages/crdt_lf_flutter)),
and put the binder above the toolbar and the editor:

```dart
import 'package:crdt_lf/crdt_lf.dart' hide ChangeSource;
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_quill/crdt_lf_quill.dart';
import 'package:flutter_quill/flutter_quill.dart';

final document = CRDTDocument();
CRDTFugueRichTextHandler(document, 'page');
final controller = QuillController.basic();

CrdtProvider.value(
  value: document,
  child: CrdtQuillBinder(
    id: 'page',
    controller: controller,
    builder: (context) => Column(
      children: [
        QuillSimpleToolbar(controller: controller),
        Expanded(
          child: QuillEditor.basic(
            controller: controller,
            // A peer's embed of a type without a builder shows a small box.
            config: QuillEditorConfig(
              unknownEmbedBuilder: crdtQuillUnknownEmbedBuilder(),
            ),
          ),
        ),
      ],
    ),
  ),
);
```

Edits made in the editor go into the handler. Changes from other peers
(`applyChange`, `importChanges`) show up in the editor.

Without `crdtQuillUnknownEmbedBuilder`, `QuillEditor` throws in its build as
soon as a peer writes an embed it has no builder for, and the base editor has
no builder for images or videos.

A change that arrives during a build (the first read of the handler, a new
controller, a write made in `initState`) reaches the editor at the end of that
frame, so a widget that listens to the controller can sit anywhere.

`crdt_lf` and `flutter_quill` both export a `ChangeSource`. If you import both
libraries in one file, hide the `crdt_lf` one, as above: Quill code uses the
Quill `ChangeSource`.

## How it works

The binder gives the controller its own `Document`. That document writes every
local change into the handler right after Quill applies it, in one
transaction. A remote change becomes a Quill delta, applied as
`ChangeSource.remote`. When the binder reads the whole handler again, it
applies the difference as `ChangeSource.silent`, so the selection stays.

Do not assign `controller.document` yourself: the new document is unbound.
Its edits stay out of the handler, and the next read of the handler replaces
it.

The converters are exported, so you can build your own binding:

- `richTextDeltaFromQuill(change, before)`: a Quill change to a `RichTextDelta`.
- `writeRichTextDelta(handler, delta)`: writes a `RichTextDelta` into the handler.
- `quillDeltaFromRichText(delta, before)`: a `RichTextDelta` to a Quill change.
- `quillDocumentFromSpans(spans)`: the handler value as a Quill document.

Pass `document:`, the Quill document `before` comes from, to the two delta
converters: an embed replaced in one change then maps to an update.

### Units

Quill counts UTF-16 code units. The handler counts runes, so an emoji is one
place in the handler and two in Quill. The converters translate the offsets
against `before`, the plain text the change applies to.

An edit always lands on whole runes. A replace that starts or ends inside a
surrogate pair takes the whole emoji, and an insert inside a pair goes before
it. A lone half surrogate stays one place in the handler.

### Attributes

Block keys (`header`, `list`, `blockquote`, `code-block`, `indent`, `align`,
`direction`, `line-height`) live on the `'\n'` that ends the line. They never
grow onto new text. Inline keys live on the text. A key with a `null` value
removes the attribute.

`quillMarkExpand(key)` says how a format grows when someone types at its edge:

| Key | Grows |
| --- | --- |
| Block keys | never (`MarkExpand.none`) |
| `link` | never (`MarkExpand.none`) |
| `style`, `displayWidth` (the size of an embed) | never (`MarkExpand.none`) |
| Any other key (`bold`, `italic`, `color`, ...) | after its end (`MarkExpand.after`) |

New text in the handler takes the formats on its left. Quill sends the exact
attributes of each insert, so after an insert `writeRichTextDelta` sets the
formats Quill asked for and removes the others. When they already match, it
writes nothing more.

### Embeds

Quill embeds (images, videos, formulas) are embeds of the handler, and back.
An embed is one position in the handler: see the "Embeds" section of the
`crdt_lf` README.

- Images and videos of `crdt_lf` (`insertImage`, `insertVideo`) and native
  Quill images and videos are the same thing. A Quill `{"image": url}` comes
  to the handler as `{"type": "image", "src": url}`, so `span.image` reads it.
  An image with only `src` goes back to Quill native; one with more fields
  (`alt`, `width`, …) comes as `{"crdt_lf": map}` (`crdtQuillEmbedType`), so
  no field is lost when Quill writes it back.
- The displayed width (`displayWidth` in the handler) is the `width` of the
  Quill `style` that the image resize writes and the image builders read. The
  rest of that `style` (height, alignment) is kept as Quill wrote it.
- Any other handler embed that is not a map of one key comes as
  `{"crdt_lf": map}` too. To show these, pass your builders through
  `crdtQuillEmbedBuilders`: the builder of the embed's `type` (or of the first
  key of the map that has one) shows it, else a small box (`fallback`). That
  builder gets one value and the style, not the other fields, and draws
  inline.
- `crdtQuillUnknownEmbedBuilder` shows every other embed with the same
  `fallback`. Without it, an embed with no builder makes `QuillEditor` throw
  in its build.

  ```dart
  QuillEditorConfig(
    embedBuilders: crdtQuillEmbedBuilders([...myBuilders]),
    unknownEmbedBuilder: crdtQuillUnknownEmbedBuilder(),
  )
  ```
- An embed replaced by another in one Quill change becomes an update of the
  same embed in the handler, so a concurrent format on it survives.
  `replaceText` with an `Embeddable` makes two Quill changes, so it is a
  delete and an insert.
- A block embed (a video, a full-width image) keeps its own `'\n'`, which
  holds the block attributes.
- `embedTypes` lists the embed types the editor may write (`image`, `video`,
  a custom `type`); `null` takes all. It filters this editor only: a peer can
  still write any type, so keep `crdtQuillUnknownEmbedBuilder` in place.
- An embed of a type out of `embedTypes`, or with data the handler refuses
  (above `maxEmbedBytes`, nested too deep, a `NaN`), goes to `onUnsupported`.
  Each embed inserted in the editor is checked this way before it is written.
  A refusal deletes no embed:
  - When nothing else is written, the whole replace is dropped: the selection
    stays, its text included, and the caret does not move.
  - When something else is written, such as the text of a paste, the selected
    text goes and the embeds of the selection stay.
- An attribute value the handler refuses (a list, a `NaN`) goes to
  `onUnsupported` as `{key: value}`. The attribute is dropped, and the rest of
  the edit is written.
- Upload and rendering stay with the app. Keep large media outside the
  document and put a URL in the embed.

### The last newline

A Quill document always ends with a `'\n'`. The handler stores that last
newline only when it is needed:

- When the last line is plain, the last `'\n'` stays out of the handler. Two
  peers that start from an empty editor do not get two newlines.
- When the last line has a block attribute (for example a heading), the
  handler stores its `'\n'` with the attribute.
- When an empty plain last line follows a line with a block attribute, the
  handler stores that last `'\n'` too. Without it, the empty line would be lost.

### Undo

The binder keeps changes from other peers out of the controller's undo stack,
like `History(userOnly: true)`. Undo takes back your own edits only, and the
undo is sent to the other peers like any other edit.

For a history that understands formats and concurrent edits, pass a
`CRDTUndoManager` to the binder. The editor then undoes through the manager,
and the toolbar buttons follow it. A new manager, or none, drops the steps of
Quill's history.

```dart
final undo = CRDTUndoManager(
  document,
  trackedOrigins: {crdtQuillOrigin}, // only the edits made in the editor
)..track(handler);

CrdtQuillBinder(id: 'page', controller: controller, undoManager: undo, ...);
```

Typing close in time is one undo step (see `captureTimeout`). Call
`undo.stopCapturing()` to end a step by hand. The toolbar buttons refresh on
editor changes only: after `undo.clear()` they keep their state until the next
change.

### Projection check

After each local write and each remote change, the binder checks that the
editor shows the handler. On a mismatch it reads the handler again. The check
compares the lengths, and also the full content while
`debugVerifyCrdtQuillProjection` is `true` (the default). The flag also works
in release builds. In [`benchmarks/results.md`](./benchmarks/results.md), a
local keystroke on a 50000-rune document takes 2.17 ms with the length check
and 3.40 ms with the full check.

### Remote cursors

The binder publishes the local selection, and `CrdtQuillCursorsOverlay` draws
the other peers' carets and selections over the editor, with the labels and
the motion of `CrdtTextCursorsOverlay`. Anchors are stable positions: they
follow any edit, and they belong on a presence channel, such as the awareness
plugin of `crdt_socket_sync`, never in the document history.

```dart
CrdtQuillBinder(
  id: 'page',
  controller: controller,
  onSelectionAnchorsChanged: (base, extent) => publishPresence(base, extent),
  child: CrdtQuillCursorsOverlay(
    id: 'page',
    cursors: remoteTextCursors, // List<CrdtTextCursor> from presence
    child: QuillEditor.basic(
      controller: controller,
      focusNode: focusNode, // kept in a State, see below
      scrollController: scrollController,
    ),
  ),
);
```

Keep the `FocusNode` and the `ScrollController` of the editor in a `State`.
Cursors change often and rebuild the editor, and `QuillEditor.basic` makes new
ones on each build when you pass none: the user would lose the keyboard after
the first keystrokes.

The callback fires while the focus is inside the binder, and once with `null`s
when the focus leaves or the handler is deleted. For mouse pointers, wrap the
editor in `CrdtAwarenessCursorsOverlay`.

## Limits

- Two peers that format the plain last line at the same time both store a
  last `'\n'`, so the document gets one extra line.
- The editor keeps its own selection, moved by each remote change.
- A remote selection is one caret high: it covers part of a line that holds a
  tall inline embed.
- Remote cursors move on document changes. After a layout change alone, such
  as an image that finishes loading, they stay until the next change.

## Example

[`example/lib/main.dart`](./example/lib/main.dart) shows two editors with
toolbars and each other's cursors, on two simulated peers of the same document.

## Apps

- [greyhound_markdown](https://github.com/MattiaPispisa/crdt/tree/main/apps/greyhound_markdown) — Real-time collaborative markdown editor built on crdt_lf

## Packages

Other bricks of the crdt "system" are:

- [crdt_lf](https://pub.dev/packages/crdt_lf)
- [crdt_socket_sync](https://pub.dev/packages/crdt_socket_sync)
- [crdt_lf_flutter](https://pub.dev/packages/crdt_lf_flutter)
- [hlc_dart](https://pub.dev/packages/hlc_dart)
- [crdt_lf_persistence](https://pub.dev/packages/crdt_lf_persistence)
- [crdt_lf_hive](https://pub.dev/packages/crdt_lf_hive)
- [crdt_lf_drift](https://pub.dev/packages/crdt_lf_drift)
- [crdt_lf_sqlite](https://pub.dev/packages/crdt_lf_sqlite)
- [crdt_socket_sync_dart_frog](https://pub.dev/packages/crdt_socket_sync_dart_frog)
- [crdt_socket_sync_serverpod](https://pub.dev/packages/crdt_socket_sync_serverpod)

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[package_badge]: https://img.shields.io/pub/v/crdt_lf_quill.svg
[codecov_badge]: https://img.shields.io/codecov/c/github/MattiaPispisa/crdt/main?flag=crdt_lf_quill&logo=codecov
[codecov_link]: https://app.codecov.io/gh/MattiaPispisa/crdt/tree/main/packages/adapters/text/crdt_lf_quill
[ci_badge]: https://img.shields.io/github/actions/workflow/status/MattiaPispisa/crdt/main.yaml
[ci_link]: https://github.com/MattiaPispisa/crdt/actions/workflows/main.yaml
[pub_points_badge]: https://img.shields.io/pub/points/crdt_lf_quill
[pub_link]: https://pub.dev/packages/crdt_lf_quill
[pub_publisher_badge]: https://img.shields.io/pub/publisher/crdt_lf_quill
[pub_publisher_link]: https://pub.dev/packages?q=publisher%3Amattiapispisa.it
[pub_likes_badge]: https://img.shields.io/pub/likes/crdt_lf_quill
