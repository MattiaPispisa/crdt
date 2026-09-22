# CRDT Socket Sync — Dart Frog

[![crdt_socket_sync_dart_frog_badge][crdt_socket_sync_dart_frog_badge]](https://pub.dev/packages/crdt_socket_sync_dart_frog) [![pub points][pub_points]][pub_link]
[![pub likes][pub_likes]][pub_link]
[![codecov][codecov_badge]][codecov_link]
[![ci_badge]][ci_link]
[![License: MIT][license_badge]][license_link]
[![pub publisher][pub_publisher]][pub_publisher_link]

[![docs_badge]][docs_link]

- [CRDT Socket Sync — Dart Frog](#crdt-socket-sync--dart-frog)
  - [What it does](#what-it-does)
  - [Installation](#installation)
  - [Quick start](#quick-start)
    - [Relay mode](#relay-mode)
    - [Server–client mode](#serverclient-mode)
  - [Authenticating before the upgrade](#authenticating-before-the-upgrade)
  - [Routing and document ids](#routing-and-document-ids)
  - [Lifecycle](#lifecycle)
  - [Two kinds of ping](#two-kinds-of-ping)
  - [Gotchas](#gotchas)
  - [Examples](#examples)
  - [Roadmap](#roadmap)

## What it does

[`crdt_socket_sync`](https://pub.dev/packages/crdt_socket_sync) ships two
WebSocket servers that own a `dart:io` `HttpServer`. Under
[Dart Frog](https://pub.dev/packages/dart_frog) the HTTP server is the
framework's, so those two are not usable: there is no server to create and no
request to upgrade yourself.

This package bridges that. It takes the session hosts from `crdt_socket_sync` —
`DocumentSessionHost` (CRDT-aware) and `RelaySessionHost` (relay) — and gives
you a Dart Frog `Handler` that upgrades the request and hands the socket over.
Everything else is unchanged: same protocol, same handshake, same plugins, same
aligned snapshots and log compaction.

It is deliberately thin. The interesting code lives in `crdt_socket_sync`;
what this adds is the seam, plus the one thing Dart Frog gives you that the
bundled servers cannot — **the request, before the socket exists**.

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

The relay never interprets CRDT data: it rebroadcasts opaque blobs to the other
clients of a room and persists them. It is the simpler of the two.

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

The CRDT-aware mode keeps the documents server-side in a `CRDTServerRegistry`,
validates changes and takes aligned snapshots.

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
[`example/`](./example) does, with Hive. A registry is opened asynchronously,
so build it in Dart Frog's `init()` (see [Lifecycle](#lifecycle)) and keep it
in a top-level `late final`.

## Authenticating before the upgrade

This is the reason to reach for Dart Frog here. The handler is just a value:
call it only once the request has earned it.

```dart
Future<Response> onRequest(RequestContext context) async {
  final token = context.request.headers['authorization'];
  if (!await isAuthorized(token)) {
    return Response(statusCode: HttpStatus.unauthorized);
  }
  return crdtSyncWebSocketHandler(context.read<DocumentSessionHost>())(context);
}
```

A rejected client gets a plain `401` and never reaches the protocol. With the
bundled `WebSocketServer` the socket is already up by the time you could look
at anything.

## Routing and document ids

The document id travels **inside** the protocol frames (the handshake in
server–client mode, the hello in relay mode), not in the URL. A single route
therefore serves every document, and this package does no routing of its own.

A parameterised route is still useful — for authorizing per document:

```dart
// routes/sync/[documentId].dart
Future<Response> onRequest(RequestContext context, String documentId) async {
  if (!await canAccess(context, documentId)) {
    return Response(statusCode: HttpStatus.forbidden);
  }
  return crdtSyncWebSocketHandler(context.read<DocumentSessionHost>())(context);
}
```

Note that the path segment is what *you* check; the host still takes the
document id from the frames.

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

## Two kinds of ping

`crdtSyncWebSocketHandler` and `crdtRelayWebSocketHandler` forward `protocols`,
`allowedOrigins` and `pingInterval` to `dart_frog_web_socket`. Set
`allowedOrigins` if browsers connect; unset, any origin may.

`pingInterval` is a **WebSocket-level** ping. It is not the protocol's own ping
(`Protocol.pingInterval`, 15s), which carries the client's version vector and
drives both liveness detection and the aligned-snapshot coordinator. They are
complementary — setting one is not a reason to drop the other.

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

- [`example/`](./example) — server–client mode on `/sync`, documents kept in
  Hive through `crdt_lf_hive`, a token check in front of the route.
- [`relay_example/`](./relay_example) — relay mode on `/relay`, rooms kept in
  memory.

```sh
cd example   # or relay_example
dart_frog dev
```

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
