# crdt_lf_flutter demo

A single-file demo (`lib/main.dart`) that exercises **every public widget of
`crdt_lf_flutter`**. Each reactive region is wrapped in a rebuild badge
(`⟳ label ×N`) that counts and flashes on every rebuild — press a button and
watch that only the widgets observing the edited handler light up.

| Card | Widget demonstrated | Badge label(s) |
| --- | --- | --- |
| AppBar summary | `CrdtBuilder` — rebuilds on **any** document change | `document` |
| Document slice | `CrdtSelector<int>` — dedups until a new handler is registered | `doc-handlers` |
| Counter | `CrdtHandlerSelector` on a `CRDTRegisterHandler<int>` | `counter` |
| Side effects | `CrdtHandlerListener` — fires a SnackBar, child never rebuilds | `listener-child` |
| Todos | `CrdtHandlerSelector` (length) + `CrdtHandlerBuilder` (list) | `todos-count`, `todos-list` |
| Settings | `CrdtHandlerBuilder` with `nested: false` vs `nested: true` on a `CRDTMapRefHandler` | `settings-flat`, `settings-nested` |
| Note | `CrdtTextFieldBuilder` bound to a `CRDTFugueTextHandler`; "Remote edit" imports a change from a throwaway peer | `note-text` |

The document is provided once at the root with `CrdtProvider`; buttons resolve
handlers imperatively via `context.crdtHandler<H>(id)` (no rebuild).

## Run

```sh
flutter run
```

## Test

`test/widget_test.dart` drives every button and asserts the exact per-badge
rebuild deltas — the scoped-re-render guarantees shown in the UI.

```sh
flutter test
```
