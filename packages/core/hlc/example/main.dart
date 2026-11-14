// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// A copy of a recipe, written by `melos run recipes_sync`.
// Edit the recipe, then run it again:
// packages/_internal/crdt_lf_recipes/lib/hybrid_clock/main.dart

import 'dart:io';

import 'package:hlc_dart/hlc_dart.dart';

/// Moves a clock through a local event and a received message.
///
/// Returns whether the message comes before the clock, and whether the 64-bit
/// and the 8-byte forms read back the same clock, in this order.
List<bool> runClock() {
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

  return [ordered, fromInt == clock, fromBytes == clock];
}

void main() {
  runClock();
}
