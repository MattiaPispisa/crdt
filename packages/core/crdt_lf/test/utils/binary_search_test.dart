import 'package:crdt_lf/src/utils/binary_search.dart';
import 'package:test/test.dart';

void main() {
  group('lowerBoundBy', () {
    int compare(int element, int target) => element.compareTo(target);

    test('returns 0 on an empty list', () {
      expect(<int>[].lowerBoundBy(5, compare), 0);
    });

    test('returns the index of an exact match', () {
      expect([1, 3, 5, 7, 9].lowerBoundBy(5, compare), 2);
    });

    test('returns the leftmost index among duplicates', () {
      expect([1, 3, 3, 3, 5].lowerBoundBy(3, compare), 1);
    });

    test('returns 0 when target is smaller than every element', () {
      expect([3, 5, 7].lowerBoundBy(0, compare), 0);
    });

    test('returns length when target is larger than every element', () {
      expect([3, 5, 7].lowerBoundBy(10, compare), 3);
    });

    test('finds the insertion point between elements', () {
      expect([1, 3, 5, 7].lowerBoundBy(4, compare), 2);
    });

    test('restricts the search to [start, end)', () {
      final list = [0, 0, 2, 4, 6, 0, 0];
      expect(list.lowerBoundBy(4, compare, start: 2, end: 5), 3);
    });

    test('a comparator that never returns 0 yields a strict upper bound', () {
      // c > target ? 1 : -1 finds the first element strictly greater than
      // target, even when target is present in the list.
      int strictlyAfter(int element, int target) =>
          element > target ? 1 : -1;

      expect([1, 3, 3, 5].lowerBoundBy(3, strictlyAfter), 3);
      expect([1, 3, 3, 5].lowerBoundBy(0, strictlyAfter), 0);
      expect([1, 3, 3, 5].lowerBoundBy(5, strictlyAfter), 4);
    });
  });
}
