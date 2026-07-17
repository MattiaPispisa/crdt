# Hybrid Logical Clock

[![hlc_dart_badge][hlc_dart_badge]](https://pub.dev/packages/hlc_dart)
[![pub points][pub_points]][pub_link]
[![pub likes][pub_likes]][pub_link]
[![codecov][codecov_badge]][codecov_link]
[![ci_badge][ci_badge]][ci_link]
[![License: MIT][license_badge]][license_link]
[![pub publisher][pub_publisher]][pub_publisher_link]

[![docs_badge]][docs_link]

- [Hybrid Logical Clock](#hybrid-logical-clock)
  - [Features](#features)
  - [Getting Started](#getting-started)
  - [Usage](#usage)
    - [Basic Usage](#basic-usage)
    - [Complete Example](#complete-example)
  - [Roadmap](#roadmap)
  - [Packages](#packages)


A hybrid logical clock implementation in Dart based on the paper
[Logical Physical Clocks and Consistent Snapshots in Globally Distributed Databases](https://cse.buffalo.edu/tech-reports/2014-04.pdf).

This library provides a Hybrid Logical Clock (HLC) implementation that combines the benefits of logical clocks and physical clocks:
- Captures causality like logical clocks (e hb f => l.e < l.f)
- Maintains closeness to physical/NTP time (l.e is close to pt.e)
- Compatible with 64-bit NTP timestamp format
- Works in peer-to-peer architectures without a central server

## Features

- Local event handling
- Message exchange between peers
- Causality detection
- Serialization to/from 64-bit integers (`toInt64` / `fromInt64`)
- Compact 8-byte big-endian binary representation (`toUint8List` / `fromUint8List`) — usable as a building block inside larger binary frames (e.g. `OperationId` in `crdt_lf`)
- Thread-safe implementation
- Zero dependencies
- Drift detection
- Mutable and immutable methods for every needed operation

## Getting Started

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  hlc_dart: 
```

## Usage

### Basic Usage

```dart
import 'package:hlc_dart/hlc_dart.dart';

// Create a new HLC initialized to the current time
final clock = HybridLogicalClock.now();

// Handle a local event
clock.localEvent(DateTime.now().millisecondsSinceEpoch);

// Handle receiving a message from another peer
final receivedClock = HybridLogicalClock.now();
clock.receiveEvent(DateTime.now().millisecondsSinceEpoch, receivedClock);

// Check causality
print(clock.happenedBefore(receivedClock));
print(clock.happenedAfter(receivedClock));
print(clock.isConcurrentWith(receivedClock));
print(clock >= receivedClock);
print(clock < receivedClock);

// Serialize/deserialize as a 64-bit integer
final serialized = clock.toInt64();
final deserialized = HybridLogicalClock.fromInt64(serialized);

// Or as a compact 8-byte big-endian buffer (useful when embedding an HLC
// inside a larger binary frame).
final bytes = clock.toUint8List();
final fromBytes = HybridLogicalClock.fromUint8List(bytes);
```

### [Complete Example](https://github.com/MattiaPispisa/crdt/blob/main/packages/hlc/example/main.dart)

## Roadmap
A roadmap is available in the [project](https://github.com/users/MattiaPispisa/projects/1) page. The roadmap provides a high-level overview of the project's goals and the current status of the project.

## Packages

Other bricks of the crdt "system" are:

- [crdt_lf](https://pub.dev/packages/crdt_lf)
- [crdt_socket_sync](https://pub.dev/packages/crdt_socket_sync)
- [crdt_lf_flutter](https://pub.dev/packages/crdt_lf_flutter)
- [crdt_lf_hive](https://pub.dev/packages/crdt_lf_hive)
- [crdt_lf_drift](https://pub.dev/packages/crdt_lf_drift)
- [crdt_lf_sqlite](https://pub.dev/packages/crdt_lf_sqlite)

[ci_badge]: https://img.shields.io/github/actions/workflow/status/MattiaPispisa/crdt/main.yaml
[ci_link]: https://github.com/MattiaPispisa/crdt/actions/workflows/main.yaml
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[hlc_dart_badge]: https://img.shields.io/pub/v/hlc_dart.svg
[codecov_badge]: https://img.shields.io/codecov/c/github/MattiaPispisa/crdt/main?flag=hlc_dart&logo=codecov
[codecov_link]: https://app.codecov.io/gh/MattiaPispisa/crdt/tree/main/packages/hlc
[pub_points]: https://img.shields.io/pub/points/hlc_dart
[pub_link]: https://pub.dev/packages/hlc_dart
[pub_publisher]: https://img.shields.io/pub/publisher/hlc_dart
[pub_publisher_link]: https://pub.dev/packages?q=publisher%3Amattiapispisa.it
[pub_likes]: https://img.shields.io/pub/likes/hlc_dart
[docs_badge]: https://img.shields.io/badge/docs-crdt-blue?style=for-the-badge&logo=read-the-docs
[docs_link]: https://mattiapispisa.it/crdt/
