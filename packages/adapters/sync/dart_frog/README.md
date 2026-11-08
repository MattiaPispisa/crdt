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
dart pub add crdt_socket_sync_dart_frog
```

```dart
// lib/src/host.dart — built once, shared by every request
final relayHost = RelaySessionHost(store: InMemoryRelayStore());

// routes/_middleware.dart
Handler middleware(Handler handler) {
  return handler.use(crdtRelayHostProvider(relayHost));
}

// routes/relay.dart
Future<Response> onRequest(RequestContext context) async {
  return crdtRelayWebSocketHandler(context.read<RelaySessionHost>())(context);
}
```

Clients connect with `WebSocketRelayClient`, pointed at `ws://localhost:8080/relay`.

## Documentation

- [Server frameworks](https://mattiapispisa.it/crdt/docs/connectors/sync/server-frameworks): both modes,
  authentication, lifecycle, gotchas
- [Sync overview](https://mattiapispisa.it/crdt/docs/connectors/sync): server–client or relay?
- Runnable servers: [`example/`](https://github.com/MattiaPispisa/crdt/tree/main/packages/adapters/sync/dart_frog/example)
  (server–client, Hive) and
  [`relay_example/`](https://github.com/MattiaPispisa/crdt/tree/main/packages/adapters/sync/dart_frog/relay_example)

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
