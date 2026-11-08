# CRDT Socket Sync — Serverpod

[![crdt_socket_sync_serverpod_badge][crdt_socket_sync_serverpod_badge]](https://pub.dev/packages/crdt_socket_sync_serverpod) [![pub points][pub_points]][pub_link]
[![pub likes][pub_likes]][pub_link]
[![codecov][codecov_badge]][codecov_link]
[![ci_badge]][ci_link]
[![License: MIT][license_badge]][license_link]
[![pub publisher][pub_publisher]][pub_publisher_link]

Serve [`crdt_socket_sync`](https://pub.dev/packages/crdt_socket_sync) sessions
from a [**Serverpod**](https://serverpod.dev) web server: your
[`crdt_lf`](https://pub.dev/packages/crdt_lf) documents stay in sync through the
pod you already have.

<div align="center">

[![Read the full documentation][docs_badge]][docs_link]

</div>

> **📖 The full guide — both modes, authentication, lifecycle, gotchas — is on [mattiapispisa.it/crdt](https://mattiapispisa.it/crdt/docs/connectors/sync/server-frameworks).**

## Features

- 🚀 **Ready-made web routes**: `CrdtSyncRoute` (server–client) and `CrdtRelayRoute` (relay)
- 🔐 **Your authentication**: subclass the route and refuse before the upgrade
- 🛑 **Clean shutdown**: dispose the host in Serverpod's shutdown tasks
- 💾 **Persistent rooms**: a `PersistentServerRegistry` on Hive, SQLite or Drift
- 📱 **Plain clients**: `WebSocketClient` / `WebSocketRelayClient`, nothing Serverpod-specific

## Quick start (relay mode)

```sh
dart pub add crdt_socket_sync_serverpod
```

```dart
Future<void> main(List<String> args) async {
  final relayHost = RelaySessionHost(store: InMemoryRelayStore());

  final pod = Serverpod(args, Protocol(), Endpoints());
  pod.webServer.addRoute(CrdtRelayRoute(relayHost), '/relay');

  await pod.start();
}
```

Clients connect with `WebSocketRelayClient`, pointed at the web server's `/relay`.

## Documentation

- [Server frameworks](https://mattiapispisa.it/crdt/docs/connectors/sync/server-frameworks): both modes,
  authentication, lifecycle, gotchas
- [Sync overview](https://mattiapispisa.it/crdt/docs/connectors/sync): server–client or relay?
- Runnable servers: [`example/`](https://github.com/MattiaPispisa/crdt/tree/main/packages/adapters/sync/serverpod/example)
  (server–client, Hive) and
  [`relay_example/`](https://github.com/MattiaPispisa/crdt/tree/main/packages/adapters/sync/serverpod/relay_example)

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
[docs_badge]: https://img.shields.io/badge/%F0%9F%93%96%20Read%20the%20full%20documentation-mattiapispisa.it%2Fcrdt-d04848?style=for-the-badge
[docs_link]: https://mattiapispisa.it/crdt/docs/connectors/sync/server-frameworks
