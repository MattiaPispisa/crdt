import 'package:test/test.dart';
import 'package:hlc_dart/hlc_dart.dart';

void main() {
  group('HybridLogicalClock', () {
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

    test('fromInt64 correctly parses 64-bit integer', () {
      final l = 0x1234567890AB;
      final c = 0xCDEF;
      final value = (l << 16) | c;

      final hlc = HybridLogicalClock.fromInt64(value);
      expect(hlc.l, equals(l));
      expect(hlc.c, equals(c));
    });

    group('parse', () {
      test('correctly parses string representation', () {
        final hlc = HybridLogicalClock.parse('1234567890.42');
        expect(hlc.l, equals(1234567890));
        expect(hlc.c, equals(42));
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

      test('throws FormatException for invalid format - non-numeric logical time', () {
        expect(
          () => HybridLogicalClock.parse('abc.42'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws FormatException for invalid format - non-numeric counter', () {
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
        final hlc = HybridLogicalClock(l: 1000, c: 5);
        hlc.localEvent(500);

        expect(hlc.l, equals(1000));
        expect(hlc.c, equals(6));
      });

      test('resets counter when physical time is greater than logical time',
          () {
        final hlc = HybridLogicalClock(l: 1000, c: 5);
        hlc.localEvent(2000);

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
    });

    test('toInt64 correctly converts to 64-bit integer', () {
      final l = 0x1234567890AB;
      final c = 0xCDEF;
      final hlc = HybridLogicalClock(l: l, c: c);

      final value = hlc.toInt64();
      expect((value >> 16) & 0xFFFFFFFFFFFF, equals(l));
      expect(value & 0xFFFF, equals(c));
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
  });
}
