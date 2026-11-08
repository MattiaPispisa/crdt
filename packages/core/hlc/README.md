# Hybrid Logical Clock

[![hlc_dart_badge][hlc_dart_badge]](https://pub.dev/packages/hlc_dart)
[![pub points][pub_points]][pub_link]
[![pub likes][pub_likes]][pub_link]
[![codecov][codecov_badge]][codecov_link]
[![ci_badge][ci_badge]][ci_link]
[![License: MIT][license_badge]][license_link]
[![pub publisher][pub_publisher]][pub_publisher_link]

A **hybrid logical clock** (HLC) for Dart: a causal order of events across
peers, close to physical time, in 64 bits, with no central server. Based on
[Logical Physical Clocks and Consistent Snapshots in Globally Distributed Databases](https://cse.buffalo.edu/tech-reports/2014-04.pdf).

<div align="center">

[![Read the full documentation][docs_badge]][docs_link]

</div>

> **📖 The full documentation, and how the CRDT engine uses this clock, is on [mattiapispisa.it/crdt](https://mattiapispisa.it/crdt/docs/deep-dive/time-hlc).**

## Features

- 🔗 **Causality**: if `e` happened before `f`, then `e < f`
- 🕰️ **Close to physical time**: 48 bits of milliseconds, 16 bits of counter
- 📡 **Peer to peer**: local events and messages between peers, no central server
- 🔢 **Total order**: `compareTo`, `<`, `>`, `max`, `min`
- 💾 **Compact**: a 64-bit integer, or 8 big-endian bytes; a full counter never wraps
- 🧭 **Drift detection**
- 🪶 **Zero dependencies**

## Quick start

```sh
dart pub add hlc_dart
```

```dart
import 'package:hlc_dart/hlc_dart.dart';

final clock = HybridLogicalClock.now();

// A local event.
clock.localEvent(DateTime.now().millisecondsSinceEpoch);

// A message from another peer.
final received = HybridLogicalClock.now();
clock.receiveEvent(DateTime.now().millisecondsSinceEpoch, received);

print(clock.happenedBefore(received));

// 64 bits, or 8 bytes.
final restored = HybridLogicalClock.fromInt64(clock.toInt64());
final bytes = clock.toUint8List();
```

A [complete example](https://github.com/MattiaPispisa/crdt/blob/main/packages/core/hlc/example/main.dart)
and the [benchmarks](https://github.com/MattiaPispisa/crdt/tree/main/packages/core/hlc/benchmarks/results.md)
are in the repository.

## Used by

[`crdt_lf`](https://pub.dev/packages/crdt_lf) stamps every change with this
clock: [how it uses it](https://mattiapispisa.it/crdt/docs/deep-dive/time-hlc#how-the-engine-uses-it).

## Apps

- [greyhound_markdown](https://github.com/MattiaPispisa/crdt/tree/main/apps/greyhound_markdown) — Real-time collaborative markdown editor built on crdt_lf

## Packages

Other bricks of the crdt "system" are:

- [crdt_lf](https://pub.dev/packages/crdt_lf)
- [crdt_socket_sync](https://pub.dev/packages/crdt_socket_sync)
- [crdt_lf_flutter](https://pub.dev/packages/crdt_lf_flutter)
- [crdt_lf_persistence](https://pub.dev/packages/crdt_lf_persistence)
- [crdt_lf_hive](https://pub.dev/packages/crdt_lf_hive)
- [crdt_lf_drift](https://pub.dev/packages/crdt_lf_drift)
- [crdt_lf_sqlite](https://pub.dev/packages/crdt_lf_sqlite)
- [crdt_socket_sync_dart_frog](https://pub.dev/packages/crdt_socket_sync_dart_frog)
- [crdt_socket_sync_serverpod](https://pub.dev/packages/crdt_socket_sync_serverpod)

[ci_badge]: https://img.shields.io/github/actions/workflow/status/MattiaPispisa/crdt/main.yaml
[ci_link]: https://github.com/MattiaPispisa/crdt/actions/workflows/main.yaml
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[hlc_dart_badge]: https://img.shields.io/pub/v/hlc_dart.svg
[codecov_badge]: https://img.shields.io/codecov/c/github/MattiaPispisa/crdt/main?flag=hlc_dart&logo=codecov
[codecov_link]: https://app.codecov.io/gh/MattiaPispisa/crdt/tree/main/packages/core/hlc
[pub_points]: https://img.shields.io/pub/points/hlc_dart
[pub_link]: https://pub.dev/packages/hlc_dart
[pub_publisher]: https://img.shields.io/pub/publisher/hlc_dart
[pub_publisher_link]: https://pub.dev/packages?q=publisher%3Amattiapispisa.it
[pub_likes]: https://img.shields.io/pub/likes/hlc_dart
[docs_badge]: https://img.shields.io/badge/%F0%9F%93%96%20Read%20the%20full%20documentation-mattiapispisa.it%2Fcrdt-d04848?style=for-the-badge
[docs_link]: https://mattiapispisa.it/crdt/docs/deep-dive/time-hlc
