# CRDT Socket Sync — Dart Frog

[![crdt_socket_sync_dart_frog_badge][crdt_socket_sync_dart_frog_badge]](https://pub.dev/packages/crdt_socket_sync_dart_frog) [![pub points][pub_points]][pub_link]
[![pub likes][pub_likes]][pub_link]
[![codecov][codecov_badge]][codecov_link]
[![ci_badge]][ci_link]
[![License: MIT][license_badge]][license_link]
[![pub publisher][pub_publisher]][pub_publisher_link]

[![docs_badge]][docs_link]

This package is one of the sync adapters for popular Dart server
frameworks. It keeps the documents of the [`crdt_lf`](https://pub.dev/packages/crdt_lf) library in sync
through a [Dart Frog](https://pub.dev/packages/dart_frog) backend. New to CRDTs? Start from the
[`crdt_lf`](https://pub.dev/packages/crdt_lf) documentation.

- [CRDT Socket Sync — Dart Frog](#crdt-socket-sync--dart-frog)
  - [What it does](#what-it-does)
  - [Installation](#installation)
  - [Quick start](#quick-start)
    - [Relay mode](#relay-mode)
    - [Server–client mode](#serverclient-mode)
  - [Authenticating before the upgrade](#authenticating-before-the-upgrade)
  - [Lifecycle](#lifecycle)
  - [Gotchas](#gotchas)
  - [Examples](#examples)
  - [Roadmap](#roadmap)

## What it does

[`crdt_socket_sync`](https://pub.dev/packages/crdt_socket_sync) for [Dart Frog](https://pub.dev/packages/dart_frog).

It gives Dart Frog handlers, ready to return from a route, that serve
`crdt_socket_sync` sessions: `crdtSyncWebSocketHandler` for the server–client
mode and `crdtRelayWebSocketHandler` for the relay mode, plus a middleware
provider for each host. Clients connect with the plain `WebSocketClient` /
`WebSocketRelayClient` of `crdt_socket_sync`.

- How the sync works (modes, protocol, plugins, persistence): the
  [`crdt_socket_sync`](https://pub.dev/packages/crdt_socket_sync) documentation.
- Routes, middleware, WebSocket options and server setup: the
  [Dart Frog documentation](https://dart-frog.dev).

## Installation

```sh
dart pub add crdt_socket_sync_dart_frog
```

One library per communication mode, like `crdt_socket_sync` itself:

```dart
// Server–client mode: crdtSyncWebSocketHandler, crdtSyncHostProvider,
// DocumentSessionHost
import 'package:crdt_socket_sync_dart_frog/sync.dart';

// Relay mode: crdtRelayWebSocketHandler, crdtRelayHostProvider,
// RelaySessionHost
import 'package:crdt_socket_sync_dart_frog/relay.dart';
```

## Quick start

### Relay mode

```dart
// lib/src/host.dart — built once, shared by every request
import 'package:crdt_socket_sync/relay_server.dart';

final relayHost = RelaySessionHost(store: InMemoryRelayStore());
```

```dart
// routes/_middleware.dart
import 'package:crdt_socket_sync_dart_frog/relay.dart';
import 'package:dart_frog/dart_frog.dart';

import '../lib/src/host.dart';

Handler middleware(Handler handler) {
  return handler.use(crdtRelayHostProvider(relayHost));
}
```

```dart
// routes/relay.dart
import 'package:crdt_socket_sync_dart_frog/relay.dart';
import 'package:dart_frog/dart_frog.dart';

Future<Response> onRequest(RequestContext context) async {
  return crdtRelayWebSocketHandler(context.read<RelaySessionHost>())(context);
}
```

Clients connect with `WebSocketRelayClient` from `crdt_socket_sync`, pointed at
`ws://localhost:8080/relay`.

### Server–client mode

```dart
// lib/src/host.dart
import 'package:crdt_socket_sync/server.dart';

final syncHost = DocumentSessionHost(
  serverRegistry: InMemoryCRDTServerRegistry(),
);
```

```dart
// routes/_middleware.dart
Handler middleware(Handler handler) {
  return handler.use(crdtSyncHostProvider(syncHost));
}
```

```dart
// routes/sync.dart
import 'package:crdt_socket_sync_dart_frog/sync.dart';
import 'package:dart_frog/dart_frog.dart';

Future<Response> onRequest(RequestContext context) async {
  return crdtSyncWebSocketHandler(context.read<DocumentSessionHost>())(context);
}
```

Use a persistent registry (`PersistentServerRegistry` with `crdt_lf_hive`,
`crdt_lf_sqlite`, `crdt_lf_drift`) for anything that must survive a restart —
[`example/`](https://github.com/MattiaPispisa/crdt/tree/main/packages/adapters/sync/dart_frog/example) does, with Hive. A registry is opened asynchronously,
so build it in Dart Frog's `init()` (see [Lifecycle](#lifecycle)) and keep it
in a top-level `late final`.

## Authenticating before the upgrade

The handler is a value: check the request first, and call the handler only
when the check passes.

```dart
Future<Response> onRequest(RequestContext context) async {
  final token = context.request.headers['authorization'];
  if (!await isAuthorized(token)) {
    return Response(statusCode: HttpStatus.unauthorized);
  }
  return crdtSyncWebSocketHandler(context.read<DocumentSessionHost>())(context);
}
```

A rejected client gets a plain `401` and never reaches the protocol.

## Lifecycle

Build the host once, outside the request. A host per request would give every
client its own empty room.

`start()` is optional: a host with no transport of its own starts on its first
connection. Call it explicitly from a
[custom init method](https://dart-frog.dev/advanced/custom-init-method/)
when you also want an orderly shutdown — Dart Frog has no shutdown hook, so
signals are the place for it. `init()` runs once, before the handler tree is
built; the
[custom entrypoint](https://dart-frog.dev/advanced/custom-entrypoint/)
`run()` is called again on every hot reload, so a listener registered there
would pile up:

```dart
// main.dart
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

Future<void> init(InternetAddress ip, int port) async {
  await relayHost.start();

  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      await relayHost.dispose();
      exit(0);
    });
  }
}
```

`dispose()` closes the open sessions and, in server–client mode, the registry
under them — for a durable registry that is where pending writes get flushed,
so skipping it loses data. A `RelayStore` has no close: a durable one is yours
to close after `dispose()`.

## Gotchas

- **`Handler` is ambiguous.** `crdt_lf` exports a CRDT `Handler` and `dart_frog`
  exports a request `Handler`. In a file that needs both, hide one:
  `import 'package:crdt_lf/crdt_lf.dart' hide Handler;`.
- **One plugin instance per host.** A `ServerSyncPlugin` binds to the host it is
  given to, once; handing the same instance to a second host throws a
  `LateInitializationError` far from the line that caused it.
- **A refused connection is closed, not rejected.** Once the response is a
  `101`, there is no status code left to send. A host that is stopped or
  disposed closes the socket instead, which the client sees as its stream
  ending.

## Examples

Two runnable Dart Frog projects, one per mode, each with a custom `init()`
that starts the host and a custom entrypoint:

- [`example/`](https://github.com/MattiaPispisa/crdt/tree/main/packages/adapters/sync/dart_frog/example) — server–client mode on `/sync`, documents kept in
  Hive through `crdt_lf_hive`, a token check in front of the route.
- [`relay_example/`](https://github.com/MattiaPispisa/crdt/tree/main/packages/adapters/sync/dart_frog/relay_example) — relay mode on `/relay`, rooms kept in
  memory.

```sh
cd example   # or relay_example
dart_frog dev
```

The [greyhound_markdown](https://github.com/MattiaPispisa/crdt/tree/main/apps/greyhound_markdown) app also runs locally
against a Dart Frog relay server:
[`server_dart_frog/`](https://github.com/MattiaPispisa/crdt/tree/main/apps/greyhound_markdown/server_dart_frog).

## Roadmap

A roadmap is available in the [project](https://github.com/users/MattiaPispisa/projects/1) page.

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
- [crdt_socket_sync_serverpod](https://pub.dev/packages/crdt_socket_sync_serverpod)

[crdt_socket_sync_dart_frog_badge]: https://img.shields.io/pub/v/crdt_socket_sync_dart_frog.svg
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[codecov_badge]: https://img.shields.io/codecov/c/github/MattiaPispisa/crdt/main?flag=crdt_socket_sync_dart_frog&logo=codecov
[codecov_link]: https://app.codecov.io/gh/MattiaPispisa/crdt/tree/main/packages/adapters/sync/dart_frog
[pub_link]: https://pub.dev/packages/crdt_socket_sync_dart_frog
[pub_points]: https://img.shields.io/pub/points/crdt_socket_sync_dart_frog
[pub_likes]: https://img.shields.io/pub/likes/crdt_socket_sync_dart_frog
[ci_badge]: https://img.shields.io/github/actions/workflow/status/MattiaPispisa/crdt/main.yaml
[ci_link]: https://github.com/MattiaPispisa/crdt/actions/workflows/main.yaml
[pub_publisher]: https://img.shields.io/pub/publisher/crdt_socket_sync_dart_frog
[pub_publisher_link]: https://pub.dev/packages?q=publisher%3Amattiapispisa.it
[docs_badge]: https://img.shields.io/badge/docs-crdt-blue?style=for-the-badge&logo=read-the-docs
[docs_link]: https://mattiapispisa.it/crdt/
