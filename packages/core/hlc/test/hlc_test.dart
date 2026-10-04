import 'dart:typed_data';

import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

void main() {
  const isWeb = identical(0, 0.0);
  group('HybridLogicalClock', () {
    test('throws RangeError for negative logical time', () {
      expect(
        () => HybridLogicalClock(l: -1, c: 0),
        throwsA(isA<RangeError>()),
      );
    });

    test('throws RangeError for negative counter', () {
      expect(
        () => HybridLogicalClock(l: 0, c: -1),
        throwsA(isA<RangeError>()),
      );
    });

    test('throws RangeError for a counter wider than 16 bits', () {
      expect(
        () => HybridLogicalClock(l: 0, c: 0x10000),
        throwsA(isA<RangeError>()),
      );
    });

    test('initialize creates a zero HLC', () {
      final hlc = HybridLogicalClock.initialize();
      expect(hlc.l, equals(0));
      expect(hlc.c, equals(0));
    });

    test('now creates HLC with current physical time', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final hlc = HybridLogicalClock.now();

      expect(hlc.l, greaterThanOrEqualTo(now));
      expect(hlc.c, equals(0));
    });

    test('fromHlc creates a copy of the input HLC', () {
      final hlc = HybridLogicalClock(l: 1000, c: 5);
      final copy = HybridLogicalClock.fromHlc(hlc);
      expect(copy.l, equals(hlc.l));
      expect(copy.c, equals(hlc.c));
    });

    test('fromInt64 correctly parses 64-bit integer (if not web)', () {
      final hlc = HybridLogicalClock.now();
      final hlc2 = HybridLogicalClock.fromInt64(hlc.toInt64());

      if (isWeb) {
        expect(hlc2.l, isNot(equals(hlc.l)));
      } else {
        expect(hlc2.l, equals(hlc.l));
      }
      expect(hlc2.c, equals(hlc.c));
    });

    test('fromUint8List correctly parses 8-byte buffer', () {
      final hlc = HybridLogicalClock.now();
      final hlc2 = HybridLogicalClock.fromUint8List(hlc.toUint8List());

      expect(hlc2.l, equals(hlc.l));
      expect(hlc2.c, equals(hlc.c));
    });

    test('fromUint8List throws RangeError for invalid buffer', () {
      expect(
        () => HybridLogicalClock.fromUint8List(Uint8List(7)),
        throwsA(isA<RangeError>()),
      );
    });

    group('parse', () {
      test('correctly parses string representation', () {
        final hlc = HybridLogicalClock.parse('1234567890.42');
        expect(hlc.l, equals(1234567890));
        expect(hlc.c, equals(42));
      });

      test('throws FormatException for a stored counter past 16 bits', () {
        expect(
          () => HybridLogicalClock.parse('1234567890.65536'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException for invalid format - no dot', () {
        expect(
          () => HybridLogicalClock.parse('1234567890'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException for invalid format - multiple dots', () {
        expect(
          () => HybridLogicalClock.parse('1234567890.42.1'),
          throwsA(isA<FormatException>()),
        );
      });

      test(
          'throws FormatException for invalid format '
          '- non-numeric logical time', () {
        expect(
          () => HybridLogicalClock.parse('abc.42'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException for invalid format - non-numeric counter',
          () {
        expect(
          () => HybridLogicalClock.parse('1234567890.abc'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException for invalid format - empty string', () {
        expect(
          () => HybridLogicalClock.parse(''),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('localEvent', () {
      test('increments counter when physical time is less than logical time',
          () {
        final hlc = HybridLogicalClock(l: 1000, c: 5)..localEvent(500);

        expect(hlc.l, equals(1000));
        expect(hlc.c, equals(6));
      });

      test('resets counter when physical time is greater than logical time',
          () {
        final hlc = HybridLogicalClock(l: 1000, c: 5)..localEvent(2000);

        expect(hlc.l, equals(2000));
        expect(hlc.c, equals(0));
      });
    });

    group('receiveEvent', () {
      test('handles concurrent events correctly', () {
        final hlc1 = HybridLogicalClock(l: 1000, c: 5);
        final hlc2 = HybridLogicalClock(l: 1000, c: 3);

        hlc1.receiveEvent(500, hlc2);
        expect(hlc1.l, equals(1000));
        expect(hlc1.c, equals(6));
      });

      test('updates logical time when received time is greater', () {
        final hlc1 = HybridLogicalClock(l: 1000, c: 5);
        final hlc2 = HybridLogicalClock(l: 2000, c: 3);

        hlc1.receiveEvent(500, hlc2);
        expect(hlc1.l, equals(2000));
        expect(hlc1.c, equals(4));
      });

      test('handles physical time greater than both logical times', () {
        final hlc1 = HybridLogicalClock(l: 1000, c: 5);
        final hlc2 = HybridLogicalClock(l: 2000, c: 3);

        hlc1.receiveEvent(3000, hlc2);
        expect(hlc1.l, equals(3000));
        expect(hlc1.c, equals(0));
      });

      test('handles case when physical time is between logical times', () {
        final hlc1 = HybridLogicalClock(l: 1000, c: 5);
        final hlc2 = HybridLogicalClock(l: 2000, c: 3);

        hlc1.receiveEvent(1500, hlc2);
        expect(hlc1.l, equals(2000));
        expect(hlc1.c, equals(4));
      });

      test('handles case when physical time equals logical time', () {
        final hlc1 = HybridLogicalClock(l: 1000, c: 5);
        final hlc2 = HybridLogicalClock(l: 1000, c: 3);

        hlc1.receiveEvent(1000, hlc2);
        expect(hlc1.l, equals(1000));
        expect(hlc1.c, equals(6));
      });

      test('increments counter when local logical time is greater', () {
        final hlc1 = HybridLogicalClock(l: 2000, c: 5);
        final hlc2 = HybridLogicalClock(l: 1000, c: 3);

        hlc1.receiveEvent(1500, hlc2);
        expect(hlc1.l, equals(2000));
        expect(hlc1.c, equals(6));
      });
    });

    group('comparison operations', () {
      test('happenedBefore correctly identifies causal ordering', () {
        final hlc1 = HybridLogicalClock(l: 1000, c: 5);
        final hlc2 = HybridLogicalClock(l: 1000, c: 6);
        final hlc3 = HybridLogicalClock(l: 2000, c: 0);

        expect(hlc1.happenedBefore(hlc2), isTrue);
        expect(hlc1.happenedBefore(hlc3), isTrue);
        expect(hlc3.happenedBefore(hlc1), isFalse);
      });

      test('isConcurrentWith correctly identifies concurrent events', () {
        final hlc1 = HybridLogicalClock(l: 1000, c: 5);
        final hlc2 = HybridLogicalClock(l: 1000, c: 5);
        final hlc3 = HybridLogicalClock(l: 1000, c: 6);

        expect(hlc1.isConcurrentWith(hlc2), isTrue);
        expect(hlc1.isConcurrentWith(hlc3), isFalse);
      });

      test('happenedAfter correctly identifies causal ordering', () {
        final hlc1 = HybridLogicalClock(l: 1000, c: 5);
        final hlc2 = HybridLogicalClock(l: 1000, c: 6);
        final hlc3 = HybridLogicalClock(l: 2000, c: 0);

        expect(hlc1.happenedAfter(hlc2), isFalse);
        expect(hlc1.happenedAfter(hlc3), isFalse);
        expect(hlc3.happenedAfter(hlc1), isTrue);
      });

      test('operators work correctly', () {
        final hlc1 = HybridLogicalClock(l: 1000, c: 5);
        final hlc2 = HybridLogicalClock(l: 1000, c: 6);
        final hlc3 = HybridLogicalClock(l: 2000, c: 0);

        expect(hlc1 > hlc2, isFalse);
        expect(hlc1 < hlc2, isTrue);
        expect(hlc1 == hlc2, isFalse);
        expect(hlc1 >= hlc2, isFalse);
        expect(hlc1 <= hlc2, isTrue);
        expect(hlc1 != hlc2, isTrue);
        expect(hlc1 >= hlc3, isFalse);
      });
    });

    test('copy creates a deep copy', () {
      final original = HybridLogicalClock(l: 1000, c: 5);
      final copy = original.copy();

      expect(copy.l, equals(original.l));
      expect(copy.c, equals(original.c));
      expect(copy, equals(original));
      expect(identical(copy, original), isFalse);
    });

    group('string representation and equality', () {
      test('toString returns correct format', () {
        final hlc = HybridLogicalClock(l: 1000, c: 5);
        expect(hlc.toString(), equals('1000.5'));
      });

      test('hashCode is consistent with equality', () {
        final hlc1 = HybridLogicalClock(l: 1000, c: 5);
        final hlc2 = HybridLogicalClock(l: 1000, c: 5);
        final hlc3 = HybridLogicalClock(l: 1000, c: 6);

        expect(hlc1.hashCode, equals(hlc2.hashCode));
        expect(hlc1.hashCode, isNot(equals(hlc3.hashCode)));
      });

      test('equality operator works correctly', () {
        final hlc1 = HybridLogicalClock(l: 1000, c: 5);
        final hlc2 = HybridLogicalClock(l: 1000, c: 5);
        final hlc3 = HybridLogicalClock(l: 1000, c: 6);

        expect(hlc1 == hlc2, isTrue);
        expect(hlc1 == hlc3, isFalse);
      });
    });

    group('nextTimestamp', () {
      test('creates a new instance', () {
        final hlc = HybridLogicalClock(l: 1000, c: 5);
        final next = hlc.nextTimestamp(500);
        expect(identical(hlc, next), isFalse);
      });

      test('applies localEvent logic', () {
        final hlc = HybridLogicalClock(l: 1000, c: 5);
        final next = hlc.nextTimestamp(500);
        expect(next.l, equals(1000));
        expect(next.c, equals(6));
      });

      test('does not modify the original instance', () {
        final hlc = HybridLogicalClock(l: 1000, c: 5)..nextTimestamp(500);
        expect(hlc.l, equals(1000));
        expect(hlc.c, equals(5));
      });
    });

    group('merge', () {
      test('creates a new instance', () {
        final hlc1 = HybridLogicalClock(l: 1000, c: 5);
        final hlc2 = HybridLogicalClock(l: 1000, c: 3);
        final merged = hlc1.merge(500, hlc2);
        expect(identical(hlc1, merged), isFalse);
      });

      test('applies receiveEvent logic', () {
        final hlc1 = HybridLogicalClock(l: 1000, c: 5);
        final hlc2 = HybridLogicalClock(l: 1000, c: 3);
        final merged = hlc1.merge(500, hlc2);
        expect(merged.l, equals(1000));
        expect(merged.c, equals(6));
      });

      test('does not modify the original instance', () {
        final hlc1 = HybridLogicalClock(l: 1000, c: 5);
        final hlc2 = HybridLogicalClock(l: 1000, c: 3);
        hlc1.merge(500, hlc2);
        expect(hlc1.l, equals(1000));
        expect(hlc1.c, equals(5));
      });
    });

    group('receiveEvent with maxDrift', () {
      test('throws ClockDriftException if drift is too high', () {
        final hlc1 = HybridLogicalClock.now();
        final hlc2 = HybridLogicalClock(
          l: hlc1.l + 1000,
          c: 0,
        );
        expect(
          () => hlc1.receiveEvent(
            hlc1.l,
            hlc2,
            maxDrift: const Duration(milliseconds: 500),
          ),
          throwsA(isA<ClockDriftException>()),
        );
      });

      test('does not throw if drift is within limits', () {
        final hlc1 = HybridLogicalClock.now();
        final hlc2 = HybridLogicalClock(
          l: hlc1.l + 100,
          c: 0,
        );
        expect(
          () => hlc1.receiveEvent(
            hlc1.l,
            hlc2,
            maxDrift: const Duration(milliseconds: 500),
          ),
          returnsNormally,
        );
      });

      test('exception contains correct message', () {
        final hlc1 = HybridLogicalClock.now();
        final hlc2 = HybridLogicalClock(l: hlc1.l + 1000, c: 0);
        try {
          hlc1.receiveEvent(
            hlc1.l,
            hlc2,
            maxDrift: const Duration(milliseconds: 500),
          );
        } catch (e) {
          expect(e, isA<ClockDriftException>());
          expect(
            e.toString(),
            contains('Received clock is too far in the future'),
          );
        }
      });
    });

    group('counter overflow', () {
      test('a burst of local events keeps every timestamp ordered in bytes',
          () {
        var clock = HybridLogicalClock(l: 1000, c: 0xFFFE);
        var bytes = clock.toUint8List();
        for (var i = 0; i < 3; i++) {
          final next = clock.nextTimestamp(500);
          final nextBytes = next.toUint8List();

          expect(HybridLogicalClock.fromUint8List(nextBytes), equals(next));
          expect(_compareBytes(bytes, nextBytes), lessThan(0));
          clock = next;
          bytes = nextBytes;
        }
        expect(clock, equals(HybridLogicalClock(l: 1001, c: 1)));
      });

      test('a received clock with a full counter stays behind the receiver',
          () {
        final received = HybridLogicalClock(l: 1000, c: 0xFFFF);
        final clock = HybridLogicalClock(l: 900, c: 0).merge(500, received);

        expect(clock > received, isTrue);
        expect(
          HybridLogicalClock.fromUint8List(clock.toUint8List()),
          equals(clock),
        );
      });
    });

    test('max and min fold clocks to the latest and the earliest', () {
      final first = HybridLogicalClock(l: 1000, c: 8);
      final clocks = [
        HybridLogicalClock(l: 1000, c: 7),
        first,
        HybridLogicalClock(l: 900, c: 9),
        first.copy(),
      ];

      expect(clocks.reduce(HybridLogicalClock.max), same(first));
      expect(clocks.reduce(HybridLogicalClock.min), same(clocks[2]));
    });

    test('asDateTime returns correct DateTime object', () {
      final now = DateTime.now();
      final hlc = HybridLogicalClock(l: now.millisecondsSinceEpoch, c: 5);
      expect(
        hlc.asDateTime.millisecondsSinceEpoch,
        equals(now.millisecondsSinceEpoch),
      );
    });
  });
}

int _compareBytes(Uint8List a, Uint8List b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return a[i].compareTo(b[i]);
    }
  }
  return 0;
}
