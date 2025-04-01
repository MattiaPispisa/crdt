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

    test('parse correctly parses string representation', () {
      final hlc = HybridLogicalClock.parse('1234567890.42');
      expect(hlc.l, equals(1234567890));
      expect(hlc.c, equals(42));
    });

    test('parse throws FormatException for invalid format', () {
      expect(
        () => HybridLogicalClock.parse('invalid'),
        throwsA(isA<FormatException>()),
      );
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
  });
}
