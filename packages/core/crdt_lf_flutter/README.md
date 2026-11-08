# CRDT LF Flutter

[![package badge][package_badge]][pub_link]
[![pub points][pub_points_badge]][pub_link]
[![pub likes][pub_likes_badge]][pub_link]
[![codecov][codecov_badge]][codecov_link]
[![ci badge][ci_badge]][ci_link]
[![license][license_badge]][license_link]
[![pub publisher][pub_publisher_badge]][pub_publisher_link]

**Flutter reactivity for [`crdt_lf`](https://pub.dev/packages/crdt_lf).**
Rebuild your widgets when the CRDT state changes, for the whole document or for
one handler, and bind text fields and editors to collaborative text. Built on
[`provider`](https://pub.dev/packages/provider).

<div align="center">

[![Read the full documentation][docs_badge]][docs_link]

</div>

> **📖 The full Flutter guide — widgets, delta widgets, text fields, editors, presence — is on [mattiapispisa.it/crdt](https://mattiapispisa.it/crdt/docs/connectors/flutter).**

## Features

- 🌳 **`CrdtProvider`**: provides a `CRDTDocument` to the subtree
- 🔁 **`CrdtBuilder` / `CrdtSelector`**: rebuild on every document update, or on a slice
- 🎯 **`CrdtHandlerBuilder` / `Selector` / `Listener`**: rebuild only when one handler changes, nested ones included
- 🔍 **`CrdtHandlerDeltaBuilder` / `Listener`**: follow **what** each change did, for long lists and `AnimatedList`
- ✍️ **`CrdtTextFieldBuilder`**: a `TextEditingController` bound to a text handler, IME included, zero rebuilds
- 🅱️ **`CrdtRichTextFieldBuilder`**: inline formats in a `TextField`, with undo
- 🧩 **`CrdtEditorBinder`**: the sync loop for any editor (used by [`crdt_lf_quill`](https://pub.dev/packages/crdt_lf_quill))
- 👥 **`CrdtTextCursorsOverlay` / `CrdtAwarenessCursorsOverlay`**: the other peers' carets and pointers
- ➕ **…and more**: everything else is in the [documentation][docs_link]

## See it live

**Greyhound Markdown** is built with `crdt_lf` and `crdt_lf_flutter`. Open it on
two devices, join the same room and edit together.

<div align="center">

[![Open the live demo](https://img.shields.io/badge/▶%20Open%20live%20demo-mattiapispisa.it%2Fcrdt%2Fgreyhound_markdown-2ea44f?style=for-the-badge&logo=flutter&logoColor=white)](https://mattiapispisa.it/crdt/greyhound_markdown/)

</div>

The [example app](https://github.com/MattiaPispisa/crdt/tree/main/packages/core/crdt_lf_flutter/example)
shows every widget on one screen, with a `⟳ rebuilt ×N` badge on each region:

<div align="center">
  <img width="500" alt="crdt_lf_flutter_example" src="https://raw.githubusercontent.com/MattiaPispisa/crdt/main/assets/demos/crdt_lf_flutter_example.gif">
</div>

## Quick start

```sh
flutter pub add crdt_lf crdt_lf_flutter
```

```dart
final doc = CRDTDocument();
CRDTFugueTextHandler(doc, 'note');

CrdtProvider.value(
  value: doc,
  child: CrdtTextFieldBuilder(
    id: 'note',
    builder: (context, controller) => TextField(controller: controller),
  ),
);
```

## Documentation

- [Flutter overview](https://mattiapispisa.it/crdt/docs/connectors/flutter): the provider and the rebuild widgets
- [Delta widgets](https://mattiapispisa.it/crdt/docs/connectors/flutter/delta-widgets)
- [Text fields](https://mattiapispisa.it/crdt/docs/connectors/flutter/text-fields): remote cursors, rich text
- [Editors](https://mattiapispisa.it/crdt/docs/connectors/flutter/editors) and [presence](https://mattiapispisa.it/crdt/docs/connectors/flutter/presence)
- [Benchmarks](https://mattiapispisa.it/crdt/docs/benchmarks/crdt_lf_flutter)

## Apps

- [greyhound_markdown](https://github.com/MattiaPispisa/crdt/tree/main/apps/greyhound_markdown) — Real-time collaborative markdown editor built on crdt_lf

## Packages

Other bricks of the crdt "system" are:

- [crdt_lf](https://pub.dev/packages/crdt_lf)
- [crdt_socket_sync](https://pub.dev/packages/crdt_socket_sync)
- [hlc_dart](https://pub.dev/packages/hlc_dart)
- [crdt_lf_persistence](https://pub.dev/packages/crdt_lf_persistence)
- [crdt_lf_hive](https://pub.dev/packages/crdt_lf_hive)
- [crdt_lf_drift](https://pub.dev/packages/crdt_lf_drift)
- [crdt_lf_sqlite](https://pub.dev/packages/crdt_lf_sqlite)
- [crdt_socket_sync_dart_frog](https://pub.dev/packages/crdt_socket_sync_dart_frog)
- [crdt_socket_sync_serverpod](https://pub.dev/packages/crdt_socket_sync_serverpod)

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[package_badge]: https://img.shields.io/pub/v/crdt_lf_flutter.svg
[codecov_badge]: https://img.shields.io/codecov/c/github/MattiaPispisa/crdt/main?flag=crdt_lf_flutter&logo=codecov
[codecov_link]: https://app.codecov.io/gh/MattiaPispisa/crdt/tree/main/packages/core/crdt_lf_flutter
[ci_badge]: https://img.shields.io/github/actions/workflow/status/MattiaPispisa/crdt/main.yaml
[ci_link]: https://github.com/MattiaPispisa/crdt/actions/workflows/main.yaml
[pub_points_badge]: https://img.shields.io/pub/points/crdt_lf_flutter
[pub_link]: https://pub.dev/packages/crdt_lf_flutter
[pub_publisher_badge]: https://img.shields.io/pub/publisher/crdt_lf_flutter
[pub_publisher_link]: https://pub.dev/packages?q=publisher%3Amattiapispisa.it
[pub_likes_badge]: https://img.shields.io/pub/likes/crdt_lf_flutter
[docs_badge]: https://img.shields.io/badge/%F0%9F%93%96%20Read%20the%20full%20documentation-mattiapispisa.it%2Fcrdt-d04848?style=for-the-badge
[docs_link]: https://mattiapispisa.it/crdt/docs/connectors/flutter
