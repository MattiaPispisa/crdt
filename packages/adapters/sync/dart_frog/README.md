# CRDT Socket Sync — Dart Frog

[![crdt_socket_sync_dart_frog_badge][crdt_socket_sync_dart_frog_badge]](https://pub.dev/packages/crdt_socket_sync_dart_frog) [![pub points][pub_points]][pub_link]
[![pub likes][pub_likes]][pub_link]
[![codecov][codecov_badge]][codecov_link]
[![ci_badge]][ci_link]
[![License: MIT][license_badge]][license_link]
[![pub publisher][pub_publisher]][pub_publisher_link]

Serve [`crdt_socket_sync`](https://pub.dev/packages/crdt_socket_sync) sessions
from a [**Dart Frog**](https://dart-frog.dev) backend: your
[`crdt_lf`](https://pub.dev/packages/crdt_lf) documents stay in sync through the
server you already have.

<div align="center">

[![Read the full documentation][docs_badge]][docs_link]

</div>

> **📖 The full guide — both modes, authentication, lifecycle, gotchas — is on [mattiapispisa.it/crdt](https://mattiapispisa.it/crdt/docs/connectors/sync/server-frameworks).**

## Features

- 🐸 **Ready-made handlers**: `crdtSyncWebSocketHandler` (server–client) and `crdtRelayWebSocketHandler` (relay)
- 🧩 **Middleware providers**: one host, built once, shared by every request
- 🔐 **Your authentication**: check the request, then upgrade
- 💾 **Persistent rooms**: a `PersistentServerRegistry` on Hive, SQLite or Drift
- 📱 **Plain clients**: `WebSocketClient` / `WebSocketRelayClient`, nothing Dart Frog-specific
- ➕ **…and more**: everything else is in the [documentation][docs_link]

## Quick start (relay mode)

```sh
dart pub add crdt_socket_sync crdt_socket_sync_dart_frog
```

The host, built once and shared by every request:

<!-- recipe:dart-frog-relay/lib/src/host.dart#host -->
```dart
import 'package:crdt_socket_sync/relay_server.dart';

/// The relay host for this process.
///
/// Constructed at the top level, so `_middleware.dart` finds it when Dart Frog
/// builds the handler tree; started by `init()` in `main.dart`. One instance
/// per process, shared by every request: a host per request would give each
/// client its own empty room.
///
/// The host has no socket of its own — Dart Frog upgrades the requests and
/// hands them over. The store is in-memory, so a restart loses every room;
/// there is no durable `RelayStore` in this repository yet, so a real backend
/// implements one over its database and closes it after `dispose()`.
final relayHost = RelaySessionHost(store: InMemoryRelayStore());
```
<!-- /recipe -->

The middleware puts it in the request context:

<!-- recipe:dart-frog-relay/routes/_middleware.dart#middleware -->
```dart
import 'package:crdt_socket_sync_dart_frog/relay.dart';
import 'package:crdt_socket_sync_dart_frog_relay_example/src/host.dart';
import 'package:dart_frog/dart_frog.dart';

/// Puts the host in the context, under the type `context.read` matches on.
///
/// The host is built once, at the top level of `host.dart`; this only hands
/// the same instance to every request.
Handler middleware(Handler handler) {
  return handler.use(crdtRelayHostProvider(relayHost));
}
```
<!-- /recipe -->

The route hands the WebSocket to it:

<!-- recipe:dart-frog-relay/routes/relay.dart#route -->
```dart
import 'package:crdt_socket_sync_dart_frog/relay.dart';
import 'package:dart_frog/dart_frog.dart';

/// Relay mode: the server rebroadcasts opaque CRDT blobs to the other clients
/// of a room and persists them, without ever reading them.
///
/// Connect with `WebSocketRelayClient` at `ws://localhost:8080/relay`. The
/// room is the document id inside the hello frame, not part of this path.
Future<Response> onRequest(RequestContext context) async {
  return crdtRelayWebSocketHandler(context.read<RelaySessionHost>())(context);
}
```
<!-- /recipe -->

Clients connect with `WebSocketRelayClient`, pointed at `ws://localhost:8080/relay`.
Complete backends, tested in CI:
[relay](https://mattiapispisa.it/crdt/docs/recipes/dart-frog-relay) and
[server–client, with documents on disk](https://mattiapispisa.it/crdt/docs/recipes/dart-frog-server).

## Documentation

- [Server frameworks](https://mattiapispisa.it/crdt/docs/connectors/sync/server-frameworks): both modes,
  authentication, lifecycle, gotchas
- [Sync overview](https://mattiapispisa.it/crdt/docs/connectors/sync): server–client or relay?
- Runnable servers: [`example/`](https://github.com/MattiaPispisa/crdt/tree/main/packages/adapters/sync/dart_frog/example)
  (server–client, Hive) and
  [`relay_example/`](https://github.com/MattiaPispisa/crdt/tree/main/packages/adapters/sync/dart_frog/relay_example)

## Roadmap

<div align="center">

[![Roadmap: done, in progress, to do][roadmap_badge]][roadmap_link]

</div>

🗺️ The [project board](https://github.com/users/MattiaPispisa/projects/1) shows what is done, what is in progress and
what comes next, for this package and the rest of the workspace. Missing something?
[Open an issue](https://github.com/MattiaPispisa/crdt/issues/new/choose): requests go on the board too.

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
[docs_badge]: https://img.shields.io/badge/%F0%9F%93%96%20Read%20the%20full%20documentation-mattiapispisa.it%2Fcrdt-d04848?style=for-the-badge
[docs_link]: https://mattiapispisa.it/crdt/docs/connectors/sync/server-frameworks
[roadmap_badge]: https://img.shields.io/badge/%F0%9F%97%BA%EF%B8%8F%20Roadmap-done%20%C2%B7%20in%20progress%20%C2%B7%20to%20do-d04848?style=for-the-badge
[roadmap_link]: https://github.com/users/MattiaPispisa/projects/1
