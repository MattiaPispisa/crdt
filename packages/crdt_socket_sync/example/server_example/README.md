# Server Example

A server example with a persistent registry of documents and clients that can connect to the server and sync their data.

## Features

- [x] Server with a persistent registry of documents: `HiveServerRegistry`. Created using [crdt_lf_hive](https://pub.dev/packages/crdt_lf_hive) + [hive](https://pub.dev/packages/hive)

## Usage

**server**

```sh
dart run lib/main.dart
```

**clients**

- [flutter_example](https://github.com/MattiaPispisa/crdt/tree/main/packages/crdt_socket_sync/example/flutter_example)
- [dart_example](https://github.com/MattiaPispisa/crdt/tree/main/packages/crdt_socket_sync/example/main_client.dart)