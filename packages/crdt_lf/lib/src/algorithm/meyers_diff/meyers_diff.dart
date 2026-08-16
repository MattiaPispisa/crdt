import 'dart:math' as math;

import 'package:crdt_lf/src/utils/rune_offsets.dart';

// ignore: always_use_package_imports does not work with this file
import 'ops.dart';

/// Compute Myers diff between two strings and return coalesced segments of
/// Equal, Insert, and Remove operations.
///
/// The diff runs over **runes** (Unicode code points).
/// All segment offsets are rune offsets.
///
/// ```dart
/// print(myersDiff('Hello', 'Hello')); // Prints 1 diff segment with op equal
/// print(myersDiff('Hello', 'Hello World')); // Prints 2 diff segments with op equal and insert
/// ```
List<DiffSegment> myersDiff(String oldText, String newText) {
  if (oldText == newText) {
    if (oldText.isEmpty) {
      return <DiffSegment>[];
    } else {
      final length = RuneOffsets.length(oldText);
      return <DiffSegment>[
        DiffSegment(
          op: DiffOp.equal,
          text: oldText,
          oldStart: 0,
          oldEnd: length,
          newStart: 0,
          newEnd: length,
        ),
      ];
    }
  }
  if (oldText.isEmpty) {
    return <DiffSegment>[
      DiffSegment(
        op: DiffOp.insert,
        text: newText,
        oldStart: 0,
        oldEnd: 0,
        newStart: 0,
        newEnd: RuneOffsets.length(newText),
      ),
    ];
  }
  if (newText.isEmpty) {
    return <DiffSegment>[
      DiffSegment(
        op: DiffOp.remove,
        text: oldText,
        oldStart: 0,
        oldEnd: RuneOffsets.length(oldText),
        newStart: 0,
        newEnd: 0,
      ),
    ];
  }

  final a = oldText.runes.toList();
  final b = newText.runes.toList();

  // Trim common prefix and suffix to reduce the problem size.
  final prefixLen = _commonPrefix(a, b);
  final suffixLen = _commonSuffix(
    a,
    b,
    prefixLen,
  );

  final segments = <DiffSegment>[];
  if (prefixLen > 0) {
    segments.add(
      DiffSegment(
        op: DiffOp.equal,
        text: String.fromCharCodes(a.getRange(0, prefixLen)),
        oldStart: 0,
        oldEnd: prefixLen,
        newStart: 0,
        newEnd: prefixLen,
      ),
    );
  }

  final aMid = a.sublist(prefixLen, a.length - suffixLen);
  final bMid = b.sublist(prefixLen, b.length - suffixLen);

  if (aMid.isEmpty && bMid.isNotEmpty) {
    segments.add(
      DiffSegment(
        op: DiffOp.insert,
        text: String.fromCharCodes(bMid),
        oldStart: prefixLen,
        oldEnd: prefixLen,
        newStart: prefixLen,
        newEnd: b.length - suffixLen,
      ),
    );
  } else if (bMid.isEmpty && aMid.isNotEmpty) {
    segments.add(
      DiffSegment(
        op: DiffOp.remove,
        text: String.fromCharCodes(aMid),
        oldStart: prefixLen,
        oldEnd: a.length - suffixLen,
        newStart: prefixLen,
        newEnd: prefixLen,
      ),
    );
  } else if (aMid.isNotEmpty || bMid.isNotEmpty) {
    final edits = _shortestEditScript(aMid, bMid);
    segments.addAll(_coalesce(aMid, bMid, edits, prefixLen, prefixLen));
  }

  if (suffixLen > 0) {
    final oldSuffixStart = a.length - suffixLen;
    final newSuffixStart = b.length - suffixLen;
    segments.add(
      DiffSegment(
        op: DiffOp.equal,
        text: String.fromCharCodes(a.getRange(oldSuffixStart, a.length)),
        oldStart: oldSuffixStart,
        oldEnd: a.length,
        newStart: newSuffixStart,
        newEnd: b.length,
      ),
    );
  }

  return segments;
}

int _commonPrefix(List<int> a, List<int> b) {
  final n = math.min(a.length, b.length);
  var i = 0;
  while (i < n && a[i] == b[i]) {
    i++;
  }
  return i;
}

int _commonSuffix(List<int> a, List<int> b, int skipPrefix) {
  final aLen = math.max(0, a.length - skipPrefix);
  final bLen = math.max(0, b.length - skipPrefix);

  var i = 0;
  while (i < aLen && i < bLen && a[a.length - 1 - i] == b[b.length - 1 - i]) {
    i++;
  }
  return i;
}

/// Internal representation of an edit along the SES: Delete or Insert.
enum _EditKind { delete, insert }

class _Edit {
  const _Edit(this.kind, this.x, this.y);

  final _EditKind kind;

  /// Position in a after applying prior edits
  final int x;

  /// Position in b after applying prior edits
  final int y;
}

/// Myers shortest edit script for two sequences of runes.
List<_Edit> _shortestEditScript(List<int> a, List<int> b) {
  final n = a.length;
  final m = b.length;
  final maxD = n + m;
  final offset = maxD;
  final v = List<int>.filled(2 * maxD + 1, 0);
  final trace = <List<int>>[];

  var finished = false;
  for (var d = 0; d <= maxD; d++) {
    for (var k = -d; k <= d; k += 2) {
      final kIndex = k + offset;
      int x;
      if (k == -d || (k != d && v[kIndex - 1] < v[kIndex + 1])) {
        x = v[kIndex + 1];
      } else {
        x = v[kIndex - 1] + 1;
      }
      var y = x - k;
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }
      v[kIndex] = x;
      if (x >= n && y >= m) {
        finished = true;
      }
    }
    trace.add(List<int>.from(v));
    if (finished) {
      break;
    }
  }
  return _reconstructEdits(trace, a, b);
}

List<_Edit> _reconstructEdits(List<List<int>> trace, List<int> a, List<int> b) {
  final n = a.length;
  final m = b.length;
  final offset = n + m;
  var x = n;
  var y = m;
  final result = <_Edit>[];
  for (var d = trace.length - 1; d > 0; d--) {
    final vPrev = trace[d - 1];
    final k = x - y;
    int prevK;
    // Choose the direction we came from based on previous layer values.
    if (k == -d || (k != d && vPrev[k - 1 + offset] < vPrev[k + 1 + offset])) {
      prevK = k + 1; // came from down (insertion)
    } else {
      prevK = k - 1; // came from right (deletion)
    }
    final prevX = vPrev[prevK + offset];
    final prevY = prevX - prevK;
    // Walk back along diagonal for equal elements
    while (x > prevX && y > prevY) {
      x--;
      y--;
      // diagonal move (match)
    }
    // Now we are at a non-diagonal move
    if (x == prevX) {
      // Insertion in b at y - 1 (we moved down to reach current k)
      result.add(_Edit(_EditKind.insert, x, y - 1));
      y--;
    } else {
      // Deletion from a at x - 1 (we moved right to reach current k)
      result.add(_Edit(_EditKind.delete, x - 1, y));
      x--;
    }
  }
  return result.reversed.toList();
}

List<DiffSegment> _coalesce(
  List<int> a,
  List<int> b,
  List<_Edit> edits,
  int oldOffset,
  int newOffset,
) {
  final out = <DiffSegment>[];
  var ax = 0;
  var by = 0;

  void push(
    DiffOp op,
    String text,
    int oldStart,
    int oldEnd,
    int newStart,
    int newEnd,
  ) {
    if (text.isEmpty) {
      return;
    }
    if (out.isNotEmpty && out.last.op == op) {
      final last = out.last;
      out[out.length - 1] = DiffSegment(
        op: op,
        text: last.text + text,
        oldStart: last.oldStart,
        oldEnd: oldEnd,
        newStart: last.newStart,
        newEnd: newEnd,
      );
      return;
    }
    out.add(
      DiffSegment(
        op: op,
        text: text,
        oldStart: oldStart,
        oldEnd: oldEnd,
        newStart: newStart,
        newEnd: newEnd,
      ),
    );
  }

  for (final e in edits) {
    final x = e.x;
    final y = e.y;
    if (ax < x && by < y) {
      final shared = String.fromCharCodes(a.getRange(ax, x));
      push(
        DiffOp.equal,
        shared,
        oldOffset + ax,
        oldOffset + x,
        newOffset + by,
        newOffset + y,
      );
      ax = x;
      by = y;
    }
    if (e.kind == _EditKind.delete) {
      final del = String.fromCharCodes(a.getRange(ax, ax + 1));
      push(
        DiffOp.remove,
        del,
        oldOffset + ax,
        oldOffset + ax + 1,
        newOffset + by,
        newOffset + by,
      );
      ax += 1;
    } else {
      final ins = String.fromCharCodes(b.getRange(by, by + 1));
      push(
        DiffOp.insert,
        ins,
        oldOffset + ax,
        oldOffset + ax,
        newOffset + by,
        newOffset + by + 1,
      );
      by += 1;
    }
  }

  // Invariant: after `_commonPrefix`/`_commonSuffix` trim the inner SES
  // always reaches the end of both sequences, so there are no residual
  // characters left to emit.
  assert(
    ax == a.length && by == b.length,
    'SES did not cover the entire inputs',
  );
  return out;
}
