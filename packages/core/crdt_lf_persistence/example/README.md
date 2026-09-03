# crdt_lf_persistence example

`bin/local_first.dart` is the local-only use case: a document, a file, and
nothing else. Run it twice to see the note come back.

```sh
dart run example/bin/local_first.dart "first line"
dart run example/bin/local_first.dart "second line"
```

Delete `note.crdt` to start over.
