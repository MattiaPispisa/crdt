import 'dart:math';

/// Hybrid Logical Clock implementation based on the paper
/// [Logical Physical Clocks and Consistent Snapshots in Globally Distributed Databases](https://cse.buffalo.edu/tech-reports/2014-04.pdf)
///
/// [HybridLogicalClock] combines the benefits of logical clocks and physical clocks:
/// - Captures causality like logical clocks (e hb f => l.e < l.f)
/// - Maintains closeness to physical/NTP time (l.e is close to pt.e)
/// - Compatible with 64-bit NTP timestamp format
/// - Works in peer-to-peer architectures without a central server
class HybridLogicalClock with Comparable<HybridLogicalClock> {
  /// Creates a new HLC with the given logical time and counter
  HybridLogicalClock({
    required int l,
    required int c,
  })  : _c = c,
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
  int get l => _l;

  /// The counter part of the timestamp
  int _c;
  int get c => _c;

  /// Handles a local event or send event
  ///
  /// Updates the [HybridLogicalClock] based on the current physical time
  ///
  /// ```
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
  /// Updates the [HybridLogicalClock] based on the received [HybridLogicalClock] and the current physical time
  ///
  /// ```
  /// l' := l
  /// l := max(l', l_m, pt)
  /// if (l = l' = l_m) then c := max(c, c_m) + 1
  /// else if (l = l') then c := c + 1
  /// else if (l = l_m) then c := c_m + 1
  /// else c := 0
  /// ```
  void receiveEvent(int physicalTime, HybridLogicalClock received) {
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

  /// Checks if this [HybridLogicalClock] happened before another [HybridLogicalClock]
  ///
  /// Returns true if this [HybridLogicalClock] happened before the other [HybridLogicalClock]
  /// (e hb f => l.e < l.f || (l.e = l.f && c.e < c.f))
  bool happenedBefore(HybridLogicalClock other) {
    return compareTo(other) < 0;
  }

  /// Checks if this [HybridLogicalClock] is concurrent with another [HybridLogicalClock]
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
  /// Returns a negative number if this [HybridLogicalClock] is less than the other,
  /// zero if they are equal, and a positive number if this [HybridLogicalClock] is greater.
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
}
