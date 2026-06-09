import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

void main() {
  group('OpIdKey', () {
    late PeerId peerIdA;
    late PeerId peerIdB;
    late OperationId opIdA;
    late OperationId opIdB;
    late Uint8List bytesA;
    late Uint8List bytesB;

    setUp(() {
      peerIdA = PeerId.parse('1c8e0bd3-174e-4d2b-b1ea-eabf98a299cf');
      peerIdB = PeerId.parse('c7b4d5aa-06a3-47d1-9dd1-5623bacbccfd');
      opIdA = OperationId(peerIdA, HybridLogicalClock(l: 1, c: 1));
      opIdB = OperationId(peerIdB, HybridLogicalClock(l: 2, c: 0));
      bytesA = opIdA.toUint8List();
      bytesB = opIdB.toUint8List();
    });

    group('factory view', () {
      test('creates key from bytes at offset 0', () {
        final key = OpIdKey.view(bytesA);
        expect(key.toOperationId(), equals(opIdA));
      });

      test('creates key from bytes at non-zero offset', () {
        const len = OperationId.byteLength;
        final combined = Uint8List(len * 2)
          ..setRange(0, len, bytesA)
          ..setRange(len, len * 2, bytesB);
        final key = OpIdKey.view(combined, offset: len);
        expect(key.toOperationId(), equals(opIdB));
      });

      test('throws RangeError on negative offset', () {
        expect(
          () => OpIdKey.view(bytesA, offset: -1),
          throwsA(isA<RangeError>()),
        );
      });

      test('throws RangeError when offset is past end', () {
        expect(
          () => OpIdKey.view(bytesA, offset: 1),
          throwsA(isA<RangeError>()),
        );
      });

      test('throws RangeError when buffer is too short', () {
        final shortBuffer = Uint8List(OperationId.byteLength - 1);
        expect(
          () => OpIdKey.view(shortBuffer),
          throwsA(isA<RangeError>()),
        );
      });
    });

    group('factory copy', () {
      test('produces key equivalent to view', () {
        final viewKey = OpIdKey.view(bytesA);
        final copyKey = OpIdKey.copy(bytesA);
        expect(copyKey, equals(viewKey));
      });

      test('copy is detached from source buffer mutation', () {
        final buffer = Uint8List.fromList(bytesA);
        final copyKey = OpIdKey.copy(buffer);
        // Mutating original buffer should not affect copyKey.
        buffer[0] = (buffer[0] + 1) & 0xFF;
        expect(copyKey.toOperationId(), equals(opIdA));
      });
    });

    group('bytesView', () {
      test('returns view of the 24 bytes', () {
        final key = OpIdKey.view(bytesA);
        final view = key.bytesView();
        expect(view, hasLength(OperationId.byteLength));
        expect(view, equals(bytesA));
      });

      test('respects offset', () {
        const len = OperationId.byteLength;
        final combined = Uint8List(len * 2)
          ..setRange(0, len, bytesA)
          ..setRange(len, len * 2, bytesB);
        final key = OpIdKey.view(combined, offset: len);
        expect(key.bytesView(), equals(bytesB));
      });
    });

    group('toOperationId / peerId / hlc', () {
      test('decodes consistent data', () {
        final key = OpIdKey.view(bytesA);
        expect(key.toOperationId(), equals(opIdA));
        expect(key.peerId(), equals(peerIdA));
        expect(key.hlc(), equals(opIdA.hlc));
      });
    });

    group('compareTo', () {
      test('orders by HLC bytes', () {
        final earlier = OpIdKey.copy(
          OperationId(peerIdA, HybridLogicalClock(l: 1, c: 0)).toUint8List(),
        );
        final later = OpIdKey.copy(
          OperationId(peerIdA, HybridLogicalClock(l: 1, c: 1)).toUint8List(),
        );
        expect(earlier.compareTo(later), lessThan(0));
        expect(later.compareTo(earlier), greaterThan(0));
      });

      test('falls back to PeerId bytes when HLC is equal', () {
        final hlc = HybridLogicalClock(l: 5, c: 3);
        // Pick two peer ids whose first differing byte we can predict.
        final lowPeer = PeerId.parse('00000000-0000-4000-8000-000000000001');
        final highPeer = PeerId.parse('ffffffff-ffff-4fff-bfff-ffffffffffff');
        final low = OpIdKey.copy(OperationId(lowPeer, hlc).toUint8List());
        final high = OpIdKey.copy(OperationId(highPeer, hlc).toUint8List());
        expect(low.compareTo(high), lessThan(0));
        expect(high.compareTo(low), greaterThan(0));
      });

      test('returns 0 when both HLC and PeerId match', () {
        final a = OpIdKey.copy(bytesA);
        final b = OpIdKey.copy(bytesA);
        expect(a.compareTo(b), equals(0));
      });
    });

    group('happened* comparators', () {
      late OpIdKey earlier;
      late OpIdKey later;
      late OpIdKey sameAsEarlier;

      setUp(() {
        earlier = OpIdKey.copy(
          OperationId(peerIdA, HybridLogicalClock(l: 1, c: 0)).toUint8List(),
        );
        later = OpIdKey.copy(
          OperationId(peerIdA, HybridLogicalClock(l: 1, c: 1)).toUint8List(),
        );
        sameAsEarlier = OpIdKey.copy(
          OperationId(peerIdA, HybridLogicalClock(l: 1, c: 0)).toUint8List(),
        );
      });

      test('happenedBefore', () {
        expect(earlier.happenedBefore(later), isTrue);
        expect(later.happenedBefore(earlier), isFalse);
        expect(earlier.happenedBefore(sameAsEarlier), isFalse);
      });

      test('happenedAfter', () {
        expect(later.happenedAfter(earlier), isTrue);
        expect(earlier.happenedAfter(later), isFalse);
        expect(earlier.happenedAfter(sameAsEarlier), isFalse);
      });

      test('happenedAfterOrEqual', () {
        expect(later.happenedAfterOrEqual(earlier), isTrue);
        expect(earlier.happenedAfterOrEqual(sameAsEarlier), isTrue);
        expect(earlier.happenedAfterOrEqual(later), isFalse);
      });
    });

    group('equality and hashCode', () {
      test('equal keys are == and have same hashCode', () {
        final a = OpIdKey.copy(bytesA);
        final b = OpIdKey.copy(bytesA);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('identical short-circuits', () {
        final a = OpIdKey.copy(bytesA);
        // Intentionally comparing the same instance to itself
        // to exercise the identical(...) fast path of operator ==.
        // ignore: unrelated_type_equality_checks
        expect(a == a, isTrue);
      });

      test('!= with different type', () {
        final a = OpIdKey.copy(bytesA);
        // Verifying that operator == rejects non-OpIdKey operands
        // is the whole point of this test.
        // ignore: unrelated_type_equality_checks
        expect(a == 'not a key', isFalse);
      });

      test('!= when bytes differ', () {
        final a = OpIdKey.copy(bytesA);
        final b = OpIdKey.copy(bytesB);
        expect(a, isNot(equals(b)));
      });
    });

    group('toString', () {
      test('matches OperationId toString', () {
        final key = OpIdKey.view(bytesA);
        expect(key.toString(), equals(opIdA.toString()));
      });
    });
  });
}
