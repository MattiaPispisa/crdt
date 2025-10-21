import 'dart:math' as math;

import 'ops.dart';

/// Compute Myers diff between two strings and return coalesced segments of
/// Equal, Insert, and Remove operations.
List<DiffSegment> myersDiff(String oldText, String newText) {
  if (oldText == newText) {
    if (oldText.isEmpty) {
      return <DiffSegment>[];
    } else {
      return <DiffSegment>[
        DiffSegment(
          op: DiffOp.equal,
          text: oldText,
          oldStart: 0,
          oldEnd: oldText.length,
          newStart: 0,
          newEnd: newText.length,
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
        newEnd: newText.length,
      ),
    ];
  }
  if (newText.isEmpty) {
    return <DiffSegment>[
      DiffSegment(
        op: DiffOp.remove,
        text: oldText,
        oldStart: 0,
        oldEnd: oldText.length,
        newStart: 0,
        newEnd: 0,
      ),
    ];
  }

  // Trim common prefix and suffix to reduce the problem size.
  final prefixLen = _commonPrefix(oldText, newText);
  final suffixLen = _commonSuffix(
    oldText,
    newText,
    prefixLen,
  );

  final segments = <DiffSegment>[];
  if (prefixLen > 0) {
    segments.add(
      DiffSegment(
        op: DiffOp.equal,
        text: oldText.substring(0, prefixLen),
        oldStart: 0,
        oldEnd: prefixLen,
        newStart: 0,
        newEnd: prefixLen,
      ),
    );
  }

  final aMid = oldText.substring(prefixLen, oldText.length - suffixLen);
  final bMid = newText.substring(prefixLen, newText.length - suffixLen);

  if (aMid.isEmpty && bMid.isNotEmpty) {
    segments.add(
      DiffSegment(
        op: DiffOp.insert,
        text: bMid,
        oldStart: prefixLen,
        oldEnd: prefixLen,
        newStart: prefixLen,
        newEnd: newText.length - suffixLen,
      ),
    );
  } else if (bMid.isEmpty && aMid.isNotEmpty) {
    segments.add(
      DiffSegment(
        op: DiffOp.remove,
        text: aMid,
        oldStart: prefixLen,
        oldEnd: oldText.length - suffixLen,
        newStart: prefixLen,
        newEnd: prefixLen,
      ),
    );
  } else if (aMid.isNotEmpty || bMid.isNotEmpty) {
    final a = aMid.codeUnits;
    final b = bMid.codeUnits;
    final edits = _shortestEditScript(a, b);
    segments.addAll(_coalesce(a, b, edits, prefixLen, prefixLen));
  }

  if (suffixLen > 0) {
    final oldSuffixStart = oldText.length - suffixLen;
    final newSuffixStart = newText.length - suffixLen;
    segments.add(
      DiffSegment(
        op: DiffOp.equal,
        text: oldText.substring(oldSuffixStart),
        oldStart: oldSuffixStart,
        oldEnd: oldText.length,
        newStart: newSuffixStart,
        newEnd: newText.length,
      ),
    );
  }

  return _mergeAdjacent(segments);
}

int _commonPrefix(String a, String b) {
  final n = math.min(a.length, b.length);
  var i = 0;
  while (i < n) {
    if (a.codeUnitAt(i) != b.codeUnitAt(i)) {
      break;
    }
    i++;
  }
  return i;
}

int _commonSuffix(String a, String b, int skipPrefix) {
  final aLen = math.max(0, a.length - skipPrefix);
  final bLen = math.max(0, b.length - skipPrefix);

  var i = 0;
  while (i < aLen && i < bLen) {
    if (a.codeUnitAt(a.length - 1 - i) != b.codeUnitAt(b.length - 1 - i)) {
      break;
    }
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

/// Myers shortest edit script for two sequences of code units.
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

  void push(DiffOp op, String text, int oldStart, int oldEnd, int newStart, int newEnd) {
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

  for (final _Edit e in edits) {
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

  if (ax < a.length && by < b.length) {
    push(
      DiffOp.equal,
      String.fromCharCodes(a.getRange(ax, a.length)),
      oldOffset + ax,
      oldOffset + a.length,
      newOffset + by,
      newOffset + b.length,
    );
  } else if (ax < a.length) {
    push(
      DiffOp.remove,
      String.fromCharCodes(a.getRange(ax, a.length)),
      oldOffset + ax,
      oldOffset + a.length,
      newOffset + by,
      newOffset + by,
    );
  } else if (by < b.length) {
    push(
      DiffOp.insert,
      String.fromCharCodes(b.getRange(by, b.length)),
      oldOffset + ax,
      oldOffset + ax,
      newOffset + by,
      newOffset + b.length,
    );
  }
  return out;
}

List<DiffSegment> _mergeAdjacent(List<DiffSegment> segments) {
  if (segments.isEmpty) {
    return segments;
  }
  final out = <DiffSegment>[];
  var current = segments.first;
  for (var i = 1; i < segments.length; i++) {
    final next = segments[i];
    if (current.op == next.op) {
      current = DiffSegment(
        op: current.op,
        text: current.text + next.text,
        oldStart: current.oldStart,
        oldEnd: next.oldEnd,
        newStart: current.newStart,
        newEnd: next.newEnd,
      );
    } else {
      out.add(current);
      current = next;
    }
  }
  out.add(current);
  return out;
}
