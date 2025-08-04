import 'dart:math';

import 'package:hlc_dart/src/exception.dart';

/// Hybrid Logical Clock implementation based on the paper
/// [Logical Physical Clocks and Consistent Snapshots in Globally Distributed Databases](https://cse.buffalo.edu/tech-reports/2014-04.pdf)
///
/// [HybridLogicalClock] combines the benefits of
/// logical clocks and physical clocks:
/// - Captures causality like logical clocks (e hb f => l.e < l.f)
/// - Maintains closeness to physical/NTP time (l.e is close to pt.e)
/// - Compatible with 64-bit NTP timestamp format
/// - Works in peer-to-peer architectures without a central server
class HybridLogicalClock with Comparable<HybridLogicalClock> {
  /// Creates a new HLC with the given logical time and counter
  HybridLogicalClock({
    required int l,
    required int c,
  })  : assert(l >= 0, 'l must be non-negative'),
        assert(c >= 0, 'c must be non-negative'),
        _c = c,
        _l = l;

  /// Creates a new [HybridLogicalClock] initialized to zero
  factory HybridLogicalClock.initialize() => HybridLogicalClock(
        l: 0,
        c: 0,
      );

  /// Creates a new [HybridLogicalClock] from the current physical time
  factory HybridLogicalClock.now() {
    return HybridLogicalClock(
      l: DateTime.now().millisecondsSinceEpoch,
      c: 0,
    );
  }

  /// Creates a new [HybridLogicalClock] from another [HybridLogicalClock]
  factory HybridLogicalClock.fromHlc(HybridLogicalClock other) {
    return HybridLogicalClock(
      l: other.l,
      c: other.c,
    );
  }

  /// Creates an [HybridLogicalClock] from a 64-bit integer
  ///
  /// The high 48 bits represent the logical time (l)
  /// The low 16 bits represent the counter (c)
  factory HybridLogicalClock.fromInt64(int value) {
    final l = (value >> 16) & 0xFFFFFFFFFFFF;
    final c = value & 0xFFFF;
    return HybridLogicalClock(l: l, c: c);
  }

  /// Creates an [HybridLogicalClock] from a string representation
  factory HybridLogicalClock.parse(String value) {
    final parts = value.split('.');
    if (parts.length != 2) {
      throw FormatException('Invalid HLC format: $value');
    }
    return HybridLogicalClock(
      l: int.parse(parts[0]),
      c: int.parse(parts[1]),
    );
  }

  /// The logical/physical part of the timestamp
  int _l;

  /// The logical/physical part of the timestamp
  int get l => _l;

  /// The counter part of the timestamp
  int _c;

  /// The counter part of the timestamp
  int get c => _c;

  /// Handles a local event or send event
  ///
  /// Updates the [HybridLogicalClock] based on the current physical time
  ///
  /// ```dart
  /// l' := l
  /// l := max(l', pt)
  /// if (l = l') then c := c + 1
  /// else c := 0
  /// ```
  void localEvent(int physicalTime) {
    final lOld = _l;
    _l = max(lOld, physicalTime);

    if (_l == lOld) {
      _c += 1;
      return;
    }

    _c = 0;
  }

  /// Handles a receive event
  ///
  /// Updates the [HybridLogicalClock] based on
  /// the received [HybridLogicalClock] and the current physical time
  ///
  /// [maxDrift] is the maximum allowed drift between the received clock
  /// and the current physical time.
  ///
  /// If the drift is greater than [maxDrift],
  /// a [ClockDriftException] is thrown.
  ///
  /// If [maxDrift] is not provided, no check is performed.
  ///
  /// ```dart
  /// l' := l
  /// l := max(l', l_m, pt)
  /// if (l = l' = l_m) then c := max(c, c_m) + 1
  /// else if (l = l') then c := c + 1
  /// else if (l = l_m) then c := c_m + 1
  /// else c := 0
  /// ```
  void receiveEvent(
    int physicalTime,
    HybridLogicalClock received, {
    Duration? maxDrift,
  }) {
    if (maxDrift != null &&
        (received.l - physicalTime) > maxDrift.inMilliseconds) {
      throw ClockDriftException(
        'Received clock is too far in the future. '
        'Max drift is ${maxDrift.inMilliseconds}ms,'
        ' but difference was ${received.l - physicalTime}ms.',
      );
    }

    final lOld = _l;
    _l = max(max(lOld, received._l), physicalTime);

    if (_l == lOld && _l == received._l) {
      _c = max(_c, received._c) + 1;
    } else if (_l == lOld) {
      _c += 1;
    } else if (_l == received._l) {
      _c = received._c + 1;
    } else {
      _c = 0;
    }
  }

  /// Returns a new clock instance updated for a local event.
  /// Does not modify the original clock.
  ///
  /// [localEvent] can be risk when used in different part of the system
  /// because it mute the original clock.
  ///
  /// A more slow but safer approach is to use [nextTimestamp]
  ///
  /// Internally it uses [copy] to create a new instance and then
  /// calls [localEvent] on the new instance.
  HybridLogicalClock nextTimestamp(int physicalTime) {
    return copy()..localEvent(physicalTime);
  }

  /// Checks if this [HybridLogicalClock] happened
  /// before another [HybridLogicalClock]
  ///
  /// Returns true if this [HybridLogicalClock] happened
  /// before the other [HybridLogicalClock]
  /// (e hb f => l.e < l.f || (l.e = l.f && c.e < c.f))
  bool happenedBefore(HybridLogicalClock other) {
    return compareTo(other) < 0;
  }

  /// Returns a new clock instance updated
  /// after receiving an event from another node.
  ///
  /// [receiveEvent] can be risk when used in different part of the system
  /// because it mute the original clock.
  ///
  /// A more slow but safer approach is to use [merge]
  ///
  /// Internally it uses [copy] to create a new instance and then
  /// calls [receiveEvent] on the new instance.
  HybridLogicalClock merge(int physicalTime, HybridLogicalClock received) {
    return copy()..receiveEvent(physicalTime, received);
  }

  /// Checks if this [HybridLogicalClock] happened
  /// after another [HybridLogicalClock]
  ///
  /// Returns true if this [HybridLogicalClock] happened
  /// after the other [HybridLogicalClock]
  bool happenedAfter(HybridLogicalClock other) {
    return compareTo(other) > 0;
  }

  /// Checks if this [HybridLogicalClock] is concurrent
  /// with another [HybridLogicalClock]
  ///
  /// Returns true if neither [HybridLogicalClock] happened before the other
  bool isConcurrentWith(HybridLogicalClock other) {
    return compareTo(other) == 0;
  }

  /// Converts this [HybridLogicalClock] to a 64-bit integer
  ///
  /// The high 48 bits represent the logical time (l)
  /// The low 16 bits represent the counter (c)
  int toInt64() {
    // Ensure l fits in 48 bits
    final maskedL = _l & 0xFFFFFFFFFFFF;
    // Ensure c fits in 16 bits
    final maskedC = _c & 0xFFFF;
    return (maskedL << 16) | maskedC;
  }

  /// Returns the logical/physical part of the timestamp as a [DateTime] object.
  DateTime get asDateTime => DateTime.fromMillisecondsSinceEpoch(l);

  /// Returns a string representation of this [HybridLogicalClock]
  @override
  String toString() {
    return '$_l.$_c';
  }

  /// Compares two [HybridLogicalClock]s for equality
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is HybridLogicalClock && other._l == _l && other._c == _c;
  }

  /// Returns a hash code for this [HybridLogicalClock]
  @override
  int get hashCode => Object.hash(_l, _c);

  /// Creates a copy of this [HybridLogicalClock]
  HybridLogicalClock copy() => HybridLogicalClock(
        l: _l,
        c: _c,
      );

  /// Compares this [HybridLogicalClock] with another [HybridLogicalClock]
  ///
  /// Returns a negative number if this [HybridLogicalClock]
  /// is less than the other, zero if they are equal, and a positive number
  /// if this [HybridLogicalClock] is greater.
  @override
  int compareTo(HybridLogicalClock other) {
    if (_l < other._l || (_l == other._l && _c < other._c)) {
      return -1;
    }
    if (_l > other._l || (_l == other._l && _c > other._c)) {
      return 1;
    }
    return 0;
  }

  /// shortcut for [happenedAfter]
  bool operator >(HybridLogicalClock other) {
    return happenedAfter(other);
  }

  /// shortcut for [happenedBefore]
  bool operator <(HybridLogicalClock other) {
    return happenedBefore(other);
  }

  /// shortcut for [happenedAfter] or [isConcurrentWith]

  bool operator >=(HybridLogicalClock other) {
    return happenedAfter(other) || isConcurrentWith(other);
  }

  /// shortcut for [happenedBefore] or [isConcurrentWith]
  bool operator <=(HybridLogicalClock other) {
    return happenedBefore(other) || isConcurrentWith(other);
  }
}
