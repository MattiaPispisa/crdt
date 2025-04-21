# Hybrid Logical Clock

[![coverage][coverage_badge]][coverage_badge]
[![License: MIT][license_badge]][license_link]

- [Hybrid Logical Clock](#hybrid-logical-clock)
  - [Features](#features)
  - [Getting Started](#getting-started)
  - [Usage](#usage)
    - [Basic Usage](#basic-usage)
    - [Complete Example](#complete-example)


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
- Serialization to/from 64-bit integers
- Thread-safe implementation
- Zero dependencies

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
print(clock.isConcurrentWith(receivedClock));

// Serialize/deserialize
final serialized = clock.toInt64();
final deserialized = HybridLogicalClock.fromInt64(serialized);
```

### [Complete Example](https://github.com/MattiaPispisa/crdt/blob/main/packages/hlc/example/main.dart)

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[coverage_badge]: https://img.shields.io/badge/coverage-100%25-green