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
- ➕ **…and more**: everything else is in the [documentation][docs_link]

## Quick start

```sh
dart pub add hlc_dart
```

<!-- recipe:hybrid-clock/main.dart#imports,clock -->
```dart
import 'dart:io';

import 'package:hlc_dart/hlc_dart.dart';

final clock = HybridLogicalClock.now();

// Another peer has its own clock: here it lives in the same program.
final received = HybridLogicalClock.now();

// A local event: an edit, a write, anything this peer does.
clock.localEvent(DateTime.now().millisecondsSinceEpoch);
stdout.writeln(clock); // <milliseconds>.<counter>

// A message from the other peer carries its clock.
clock.receiveEvent(DateTime.now().millisecondsSinceEpoch, received);

// After the receive, the message comes before this clock.
final ordered = received.happenedBefore(clock);
stdout.writeln(ordered); // true

// 64 bits, or 8 big-endian bytes.
final fromInt = HybridLogicalClock.fromInt64(clock.toInt64());
final fromBytes = HybridLogicalClock.fromUint8List(clock.toUint8List());
stdout.writeln(fromInt == clock && fromBytes == clock); // true
```
<!-- /recipe -->

The program is a [recipe](https://mattiapispisa.it/crdt/docs/recipes/hybrid-clock),
tested in CI, and the [benchmarks](https://mattiapispisa.it/crdt/docs/benchmarks/hlc) are on the
documentation site.

## Used by

[`crdt_lf`](https://pub.dev/packages/crdt_lf) stamps every change with this
clock: [how it uses it](https://mattiapispisa.it/crdt/docs/deep-dive/time-hlc#how-the-engine-uses-it).

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
[roadmap_badge]: https://img.shields.io/badge/%F0%9F%97%BA%EF%B8%8F%20Roadmap-done%20%C2%B7%20in%20progress%20%C2%B7%20to%20do-d04848?style=for-the-badge
[roadmap_link]: https://github.com/users/MattiaPispisa/projects/1
