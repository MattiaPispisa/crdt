# CRDT Socket Sync — Serverpod

[![crdt_socket_sync_serverpod_badge][crdt_socket_sync_serverpod_badge]](https://pub.dev/packages/crdt_socket_sync_serverpod) [![pub points][pub_points]][pub_link]
[![pub likes][pub_likes]][pub_link]
[![codecov][codecov_badge]][codecov_link]
[![ci_badge]][ci_link]
[![License: MIT][license_badge]][license_link]
[![pub publisher][pub_publisher]][pub_publisher_link]

[![docs_badge]][docs_link]

This package is one of the sync adapters for popular Dart server
frameworks. It keeps the documents of the [`crdt_lf`](https://pub.dev/packages/crdt_lf) library in sync
through a [Serverpod](https://pub.dev/packages/serverpod) backend. New to CRDTs? Start from the
[`crdt_lf`](https://pub.dev/packages/crdt_lf) documentation.

- [CRDT Socket Sync — Serverpod](#crdt-socket-sync--serverpod)
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

[`crdt_socket_sync`](https://pub.dev/packages/crdt_socket_sync) for [Serverpod](https://pub.dev/packages/serverpod).

It gives Serverpod web routes, ready to add to your pod, that serve
`crdt_socket_sync` sessions: `CrdtSyncRoute` for the server–client mode and
`CrdtRelayRoute` for the relay mode. Clients connect with the plain
`WebSocketClient` / `WebSocketRelayClient` of `crdt_socket_sync`.

- How the sync works (modes, protocol, plugins, persistence): the
  [`crdt_socket_sync`](https://pub.dev/packages/crdt_socket_sync) documentation.
- Routes, sessions, authentication and server configuration: the
  [Serverpod documentation](https://docs.serverpod.dev).

## Installation

```sh
dart pub add crdt_socket_sync_serverpod
```

One library per communication mode, like `crdt_socket_sync` itself:

```dart
// Server–client mode: CrdtSyncRoute, DocumentSessionHost
import 'package:crdt_socket_sync_serverpod/sync.dart';

// Relay mode: CrdtRelayRoute, RelaySessionHost
import 'package:crdt_socket_sync_serverpod/relay.dart';
```

## Quick start

### Relay mode

```dart
import 'package:crdt_socket_sync/relay_server.dart' show InMemoryRelayStore;
import 'package:crdt_socket_sync_serverpod/relay.dart';
import 'package:serverpod/serverpod.dart';

import 'src/generated/endpoints.dart';
import 'src/generated/protocol.dart';

Future<void> main(List<String> args) async {
  final relayHost = RelaySessionHost(store: InMemoryRelayStore());

  final pod = Serverpod(args, Protocol(), Endpoints());
  pod.webServer.addRoute(CrdtRelayRoute(relayHost), '/relay');

  await pod.start();
}
```

Clients connect with `WebSocketRelayClient` from `crdt_socket_sync`, pointed at
the web server's `/relay` (`ws://localhost:8080/relay` in the examples).

### Server–client mode

```dart
import 'package:crdt_socket_sync/server.dart' show InMemoryCRDTServerRegistry;
import 'package:crdt_socket_sync_serverpod/sync.dart';

final syncHost = DocumentSessionHost(
  serverRegistry: InMemoryCRDTServerRegistry(),
);

pod.webServer.addRoute(CrdtSyncRoute(syncHost), '/sync');
```

Use a persistent registry (`PersistentServerRegistry` with `crdt_lf_hive`,
`crdt_lf_sqlite`, `crdt_lf_drift`) for anything that must survive a restart —
[`example/`](https://github.com/MattiaPispisa/crdt/tree/main/packages/adapters/sync/serverpod/example) does, with Hive.

## Authenticating before the upgrade

The route upgrades in `handleCall`. Subclass it and refuse first: a `Response`
is an ordinary HTTP answer, and `super.handleCall` is the upgrade.

```dart
class AuthSyncRoute extends CrdtSyncRoute {
  AuthSyncRoute(super.sessionHost);

  @override
  FutureOr<Result> handleCall(Session session, Request request) {
    if (!session.isUserSignedIn) {
      return Response.unauthorized();
    }
    return super.handleCall(session, request);
  }
}
```

A rejected client gets a plain `401` and never reaches the protocol.

Serverpod resolves the web route's session from the `Authorization` header,
through the `authenticationHandler` given to the `Serverpod` constructor. Set
one: without it, any request that carries the header fails with a `500`
before `handleCall` runs. A malformed header gets a `400`.

Browsers cannot set headers on a WebSocket. For a browser client, send the key
in a query parameter or a cookie, and check it yourself in `handleCall`.

## Lifecycle

Build the host once, outside the request. A host per request would give every
client its own empty room.

`start()` is optional: a host with no transport of its own starts on its first
connection. Serverpod handles `SIGINT` and `SIGTERM` by itself and runs its
shutdown tasks after the web server has stopped. That is the place to dispose
the host:

```dart
pod.experimental.shutdownTasks.addTask('crdt_sync', syncHost.dispose);
```

`shutdownTasks` is part of Serverpod's experimental API, which may change
between minor versions.

`dispose()` closes the open sessions and, in server–client mode, the registry
under them — for a durable registry that is where pending writes get flushed,
so skipping it loses data. A `RelayStore` has no close: a durable one is yours
to close after `dispose()`.

## Gotchas

- **The `Session` closes before the socket opens.** Serverpod closes it as soon
  as `handleCall` returns. Read what you need from it before the upgrade.
- **An `Authorization` header needs an `authenticationHandler`.** Serverpod's
  default handler throws, so the request fails with a `500` before the route
  runs.
- **Name clashes.** `serverpod` exports Relic's `Handler` and `Message`, which
  clash with `Handler` from `crdt_lf` and `Message` from `crdt_socket_sync`.
  In a file that needs both, hide one:
  `import 'package:serverpod/serverpod.dart' hide Message;`.
- **One plugin instance per host.** A `ServerSyncPlugin` binds to the host it is
  given to, once; handing the same instance to a second host throws a
  `LateInitializationError` far from the line that caused it.
- **A refused connection is closed, not rejected.** Once the response is a
  `101`, there is no status code left to send. A host that is stopped or
  disposed closes the socket instead, which the client sees as its stream
  ending.

## Examples

Two runnable Serverpod servers, one per mode. They build the pod without a
database and without generated code, to stay small: a real project passes its
generated `Protocol()` and `Endpoints()`.

- [`example/`](https://github.com/MattiaPispisa/crdt/tree/main/packages/adapters/sync/serverpod/example) — server–client mode on `/sync`, documents kept in
  Hive through `crdt_lf_hive`, a token check in front of the upgrade.
- [`relay_example/`](https://github.com/MattiaPispisa/crdt/tree/main/packages/adapters/sync/serverpod/relay_example) — relay mode on `/relay`, rooms kept in
  memory.

```sh
cd example   # or relay_example
dart run bin/main.dart
```

The [greyhound_markdown](https://github.com/MattiaPispisa/crdt/tree/main/apps/greyhound_markdown) app also runs locally
against a Serverpod relay server:
[`server_serverpod/`](https://github.com/MattiaPispisa/crdt/tree/main/apps/greyhound_markdown/server_serverpod).

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
- [crdt_socket_sync_dart_frog](https://pub.dev/packages/crdt_socket_sync_dart_frog)

[crdt_socket_sync_serverpod_badge]: https://img.shields.io/pub/v/crdt_socket_sync_serverpod.svg
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[codecov_badge]: https://img.shields.io/codecov/c/github/MattiaPispisa/crdt/main?flag=crdt_socket_sync_serverpod&logo=codecov
[codecov_link]: https://app.codecov.io/gh/MattiaPispisa/crdt/tree/main/packages/adapters/sync/serverpod
[pub_link]: https://pub.dev/packages/crdt_socket_sync_serverpod
[pub_points]: https://img.shields.io/pub/points/crdt_socket_sync_serverpod
[pub_likes]: https://img.shields.io/pub/likes/crdt_socket_sync_serverpod
[ci_badge]: https://img.shields.io/github/actions/workflow/status/MattiaPispisa/crdt/main.yaml
[ci_link]: https://github.com/MattiaPispisa/crdt/actions/workflows/main.yaml
[pub_publisher]: https://img.shields.io/pub/publisher/crdt_socket_sync_serverpod
[pub_publisher_link]: https://pub.dev/packages?q=publisher%3Amattiapispisa.it
[docs_badge]: https://img.shields.io/badge/docs-crdt-blue?style=for-the-badge&logo=read-the-docs
[docs_link]: https://mattiapispisa.it/crdt/
