import 'dart:math' as math;
import 'dart:typed_data';

import 'package:hlc_dart/src/exception.dart';

/// Hybrid Logical Clock implementation based on the paper
/// [Logical Physical Clocks and Consistent Snapshots in Globally Distributed Databases](https://cse.buffalo.edu/tech-reports/2014-04.pdf)
///
/// [HybridLogicalClock] combines the benefits of
/// logical clocks and physical clocks:
/// - Captures causality like logical clocks (e hb f => l.e < l.f)
/// - Maintains closeness to physical time (l.e is close to pt.e)
/// - Fits in 64 bits: 48 bits for `l`, 16 bits for `c`
/// - Works in peer-to-peer architectures without a central server
///
/// If `e` happened before `f`, then `e < f`. The reverse does not hold:
/// `e < f` also when `e` and `f` are concurrent, so the order alone
/// cannot detect concurrency.
class HybridLogicalClock with Comparable<HybridLogicalClock> {
  /// Creates a new HLC with the given logical time and counter.
  ///
  /// Throws a [RangeError] unless [l] fits in 48 bits and [c] in 16 bits,
  /// both non-negative.
  HybridLogicalClock({
    required int l,
    required int c,
  })  : _l = _inRange(l, _maxLogical, 'l'),
        _c = _inRange(c, _maxCounter, 'c');

  // Skips the range check: only for values in range by construction, such as
  // decoded bytes, where the check would cost on every decoded change.
  HybridLogicalClock._(this._l, this._c);

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
    return HybridLogicalClock._(other._l, other._c);
  }

  /// Creates an [HybridLogicalClock] from a 64-bit integer
  ///
  /// The high 48 bits represent the logical time (l)
  /// The low 16 bits represent the counter (c)
  factory HybridLogicalClock.fromInt64(int value) {
    final l = (value >> 16) & 0xFFFFFFFFFFFF;
    final c = value & 0xFFFF;
    return HybridLogicalClock._(l, c);
  }

  /// Decodes a [HybridLogicalClock] from a byte buffer (Big Endian).
  ///
  /// [bytes] The buffer containing the encoded HLC.
  /// [offset] The index in the buffer where the HLC data starts (default: 0).
  ///
  /// Throws a [RangeError] if the buffer is too short.
  factory HybridLogicalClock.fromUint8List(
    Uint8List bytes, {
    int offset = 0,
  }) {
    if (offset < 0 || offset + 8 > bytes.length) {
      throw RangeError.range(offset, 0, bytes.length - 8, 'offset');
    }

    final lHigh = (bytes[offset + 0] * 256) + bytes[offset + 1];

    final lLow = (bytes[offset + 2] * 16777216) +
        (bytes[offset + 3] * 65536) +
        (bytes[offset + 4] * 256) +
        bytes[offset + 5];

    final l = (lHigh * 4294967296) + lLow;

    final c = (bytes[offset + 6] * 256) + bytes[offset + 7];

    return HybridLogicalClock._(l, c);
  }

  /// Creates an [HybridLogicalClock] from a string representation
  ///
  /// Throws a [FormatException] when [value] is not `l.c`, or when `l` or
  /// `c` is out of range.
  factory HybridLogicalClock.parse(String value) {
    final parts = value.split('.');
    if (parts.length != 2) {
      throw FormatException('Invalid HLC format: $value');
    }
    final l = int.parse(parts[0]);
    final c = int.parse(parts[1]);
    if (l < 0 || l > _maxLogical || c < 0 || c > _maxCounter) {
      throw FormatException('HLC out of range: $value');
    }
    return HybridLogicalClock._(l, c);
  }

  static const int _maxLogical = 0xFFFFFFFFFFFF;

  static const int _maxCounter = 0xFFFF;

  static int _inRange(int value, int max, String name) {
    RangeError.checkValueInInterval(value, 0, max, name);
    return value;
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
  ///
  /// {@template hlc_counter_carry}
  /// When `c` passes 65535, `l` moves forward by 1 and `c` starts again from
  /// 0. The clock stays ahead of every input and fits in [toUint8List].
  /// {@endtemplate}
  void localEvent(int physicalTime) {
    final lOld = _l;
    _l = math.max(lOld, physicalTime);
    _c = _l == lOld ? _c + 1 : 0;
    _carryCounter();
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
  ///
  /// {@macro hlc_counter_carry}
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
    _l = math.max(math.max(lOld, received._l), physicalTime);

    if (_l == lOld && _l == received._l) {
      _c = math.max(_c, received._c) + 1;
    } else if (_l == lOld) {
      _c += 1;
    } else if (_l == received._l) {
      _c = received._c + 1;
    } else {
      _c = 0;
    }
    _carryCounter();
  }

  // The paper (§6.2) lets `c` roll over; the byte order of an id must hold.
  void _carryCounter() {
    if (_c > _maxCounter) {
      _l += 1;
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

  /// Whether this clock orders before [other].
  ///
  /// `true` for every event that happened before [other], and also for some
  /// concurrent events.
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

  /// Whether this clock orders after [other].
  ///
  /// `true` for every event that happened after [other], and also for some
  /// concurrent events.
  bool happenedAfter(HybridLogicalClock other) {
    return compareTo(other) > 0;
  }

  /// Whether this clock holds the same timestamp as [other].
  ///
  /// Equal timestamps mean concurrent events. Concurrent events with
  /// different timestamps return `false`.
  bool isConcurrentWith(HybridLogicalClock other) {
    return compareTo(other) == 0;
  }

  /// Converts this [HybridLogicalClock] to a 64-bit integer.
  ///
  /// Encoding layout:
  /// - High 48 bits: logical/physical time `l` (milliseconds)
  /// - Low 16 bits: counter `c`
  ///
  /// Remember that JSON numeric values are IEEE‑754 double precision on the web
  ///   (JavaScript number). The maximum safe integer is 2^53−1
  ///   (9,007,199,254,740,991).
  ///
  /// The packed 64‑bit value produced here commonly exceeds 2^53−1,
  /// which means it will lose precision if serialized as a JSON number
  /// and parsed in JavaScript.
  ///
  /// For network/JSON payloads, prefer [toString],
  /// [HybridLogicalClock.parse] instead.
  int toInt64() {
    // Ensure l fits in 48 bits
    final maskedL = _l & 0xFFFFFFFFFFFF;
    // Ensure c fits in 16 bits
    final maskedC = _c & 0xFFFF;
    return (maskedL << 16) | maskedC;
  }

  /// Encodes this [HybridLogicalClock] into a new 8-byte buffer (Big Endian).
  ///
  /// Respect to [toInt64], this method is safe to use in JavaScript
  /// (Web) because it reconstructs the 48-bit logical time
  /// and 16-bit counter separately,
  /// avoiding the 53-bit safe integer limit of JavaScript Numbers.
  ///
  /// Layout:
  /// - Bytes 0-5: Logical time (l) - 48 bits
  /// - Bytes 6-7: Counter (c) - 16 bits
  Uint8List toUint8List() {
    final bytes = Uint8List(8);

    // Integer division avoids float conversion on native Dart.
    // Using ~/ and % instead of (/ n).floor() keeps the result identical
    // on both VM and Web (dart2js integers are 53-bit, so ~/ 2^32 is safe
    // for any realistic timestamp value).
    final lHigh = _l ~/ 0x100000000;
    final lLow = _l % 0x100000000;

    bytes[0] = (lHigh >> 8) & 0xFF;
    bytes[1] = lHigh & 0xFF;

    bytes[2] = (lLow >> 24) & 0xFF;
    bytes[3] = (lLow >> 16) & 0xFF;
    bytes[4] = (lLow >> 8) & 0xFF;
    bytes[5] = lLow & 0xFF;

    bytes[6] = (_c >> 8) & 0xFF;
    bytes[7] = _c & 0xFF;
    return bytes;
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

  /// Returns the later of [a] and [b]; [a] when they are equal.
  static HybridLogicalClock max(HybridLogicalClock a, HybridLogicalClock b) {
    return b.compareTo(a) > 0 ? b : a;
  }

  /// Returns the earlier of [a] and [b]; [a] when they are equal.
  static HybridLogicalClock min(HybridLogicalClock a, HybridLogicalClock b) {
    return b.compareTo(a) < 0 ? b : a;
  }

  /// Creates a copy of this [HybridLogicalClock]
  HybridLogicalClock copy() => HybridLogicalClock._(_l, _c);

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
