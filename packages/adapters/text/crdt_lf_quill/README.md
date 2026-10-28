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
    - [The last newline](#the-last-newline)
    - [Undo](#undo)
    - [Projection check](#projection-check)
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
        Expanded(child: QuillEditor.basic(controller: controller)),
      ],
    ),
  ),
);
```

Edits made in the editor go into the handler. Changes from other peers
(`applyChange`, `importChanges`) show up in the editor.

Keep every widget that listens to the controller **under** the binder. The
binder loads a new controller while it builds, and a listener above it would
be marked dirty during the build. A read of the handler that arrives during a
build (the first one, for example) runs at the end of that frame.

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

### Units

Quill counts UTF-16 code units. The handler counts runes, so an emoji is one
place in the handler and two in Quill. The converters translate the offsets
against `before`, the plain text the change applies to.

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
| Any other key (`bold`, `italic`, `color`, ...) | after its end (`MarkExpand.after`) |

New text in the handler takes the formats on its left. Quill sends the exact
attributes of each insert, so after an insert `writeRichTextDelta` sets the
formats Quill asked for and removes the others. When they already match, it
writes nothing more.

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

### Projection check

After each local write and each remote change, the binder checks that the
editor shows the handler. On a mismatch it reads the handler again. The check
compares the lengths, and also the full content while
`debugVerifyCrdtQuillProjection` is `true` (the default). The flag also works
in release builds. In [`benchmarks/results.md`](./benchmarks/results.md), a
local keystroke on a 50000-rune document takes 2.17 ms with the length check
and 3.40 ms with the full check.

## Limits

- Embeds (images, videos) are not supported yet. The binder refuses an embed
  inserted through the controller and calls `onUnsupported`, so the app can
  tell the user. An embed composed into the document directly is not written
  to the handler, and the editor is read again from the handler.
- Two peers that format the plain last line at the same time both store a
  last `'\n'`, so the document gets one extra line.
- The editor keeps its own selection, moved by each remote change. Remote
  cursors are not drawn.

## Example

[`example/lib/main.dart`](./example/lib/main.dart) shows two editors with
toolbars, on two simulated peers of the same document.

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
