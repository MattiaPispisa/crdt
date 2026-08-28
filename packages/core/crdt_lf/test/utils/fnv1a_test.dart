import 'dart:convert';

import 'package:crdt_lf/src/utils/fnv1a.dart';
import 'package:test/test.dart';

void main() {
  group('fnv1a32', () {
    test('matches the reference vectors', () {
      // The published FNV-1a 32-bit test vectors.
      expect(fnv1a32(<int>[]), 0x811C9DC5);
      expect(fnv1a32(utf8.encode('a')), 0xE40C292C);
      expect(fnv1a32(utf8.encode('b')), 0xE70C2DE5);
      expect(fnv1a32(utf8.encode('foobar')), 0xBF9CF968);
    });

    test('stays inside 32 bits', () {
      final hash = fnv1a32(List<int>.generate(256, (i) => i));
      expect(hash, inInclusiveRange(0, 0xFFFFFFFF));
    });

    // `hash * prime` passes 2^53, which a JavaScript number cannot hold
    // exactly. A seed with the high bits set makes every step overflow, so a
    // build that multiplies in one go drifts away from these values on the web
    // while still passing on the VM.
    test('a high seed keeps full precision', () {
      expect(fnv1a32(<int>[0], seed: 0xFFFFFFFF), 0xFEFFFE6D);
      expect(fnv1a32(<int>[0xFF], seed: 0xFFFFFFFF), 0xFFFE6D00);
    });

    test('seeding chains two buffers into one hash', () {
      const first = <int>[1, 2, 3];
      const second = <int>[4, 5];

      expect(
        fnv1a32(second, seed: fnv1a32(first)),
        fnv1a32(<int>[...first, ...second]),
      );
    });

    test('hashes only the [start, end) window', () {
      expect(
        fnv1a32(<int>[9, 1, 2, 3, 9], start: 1, end: 4),
        fnv1a32(<int>[1, 2, 3]),
      );
    });

    test('an empty window returns the seed', () {
      expect(fnv1a32(<int>[1, 2, 3], start: 2, end: 2), fnv1a32Offset);
    });
  });
}
