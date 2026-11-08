// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'handler.dart';

class _ResolvedRun {
  _ResolvedRun(this.start, this.end, this.winners, this.attributes);

  factory _ResolvedRun.of(int start, int end, Map<String, _Mark> winners) =>
      _ResolvedRun(
        start,
        end,
        winners,
        Map.unmodifiable({
          for (final entry in winners.entries)
            if (entry.value.value != null) entry.key: entry.value.value,
        }),
      );

  int start;
  int end;
  // The newest live mark of each key over the run, null values included.
  final Map<String, _Mark> winners;
  final Map<String, Object?> attributes;

  _ResolvedRun slice(int start, int end) =>
      _ResolvedRun(start, end, winners, attributes);

  bool sameWinners(_ResolvedRun other) {
    if (identical(winners, other.winners)) {
      return true;
    }
    if (winners.length != other.winners.length) {
      return false;
    }
    for (final entry in winners.entries) {
      if (!identical(other.winners[entry.key], entry.value)) {
        return false;
      }
    }
    return true;
  }
}

class _ResolvedMarks {
  _ResolvedMarks(this.runs);

  factory _ResolvedMarks.resolve(
    FugueTree<String> tree,
    Iterable<_Mark> marks,
  ) {
    final length = tree.liveLength;
    final opens = <int, List<_Mark>>{};
    final closes = <int, List<_Mark>>{};
    for (final mark in marks) {
      final from = mark.start.liveStart(tree);
      final to = mark.end.liveEnd(tree, length);
      if (from == null || to == null || from >= to) {
        continue;
      }
      (opens[from] ??= []).add(mark);
      (closes[to] ??= []).add(mark);
    }

    final boundaries = SplayTreeSet<int>.of([0, length, ...opens.keys]);
    for (final at in closes.keys) {
      if (at < length) {
        boundaries.add(at);
      }
    }

    final active = <String, SplayTreeSet<_Mark>>{};
    final runs = <_ResolvedRun>[];
    final points = boundaries.toList();
    for (var i = 0; i + 1 < points.length; i++) {
      final at = points[i];
      for (final mark in closes[at] ?? const <_Mark>[]) {
        active[mark.key]?.remove(mark);
      }
      for (final mark in opens[at] ?? const <_Mark>[]) {
        (active[mark.key] ??= SplayTreeSet<_Mark>(_Mark.byStamp)).add(mark);
      }

      final winners = <String, _Mark>{
        for (final entry in active.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value.last,
      };

      final run = _ResolvedRun.of(at, points[i + 1], winners);
      if (runs.isNotEmpty && runs.last.sameWinners(run)) {
        runs.last.end = run.end;
      } else {
        runs.add(run);
      }
    }
    return _ResolvedMarks(runs);
  }

  final List<_ResolvedRun> runs;

  // Puts [mark] over the live range [from, to): it wins where it is newer
  // than the current winner of its key.
  void patch(_Mark mark, int from, int to) {
    if (from >= to) {
      return;
    }
    final first = _runIndexAt(from);
    final last = _runIndexAt(to - 1);
    final low = first > 0 ? first - 1 : first;
    final high = last + 1 < runs.length ? last + 2 : last + 1;

    final region = <_ResolvedRun>[];
    void push(_ResolvedRun run) {
      if (region.isNotEmpty && region.last.sameWinners(run)) {
        region.last.end = run.end;
      } else {
        region.add(run);
      }
    }

    for (var i = low; i < high; i++) {
      final run = runs[i];
      if (run.end <= from || run.start >= to) {
        push(run.slice(run.start, run.end));
        continue;
      }
      if (run.start < from) {
        push(run.slice(run.start, from));
      }
      final start = run.start < from ? from : run.start;
      final end = run.end > to ? to : run.end;
      final current = run.winners[mark.key];
      if (current == null || _Mark.byStamp(current, mark) < 0) {
        push(_ResolvedRun.of(start, end, {...run.winners, mark.key: mark}));
      } else {
        push(run.slice(start, end));
      }
      if (run.end > to) {
        push(run.slice(to, run.end));
      }
    }
    runs.replaceRange(low, high, region);
  }

  int get length => runs.isEmpty ? 0 : runs.last.end;

  Map<String, _Mark> winnersAt(int index) => runs[_runIndexAt(index)].winners;

  void insert(int at, int count, Map<String, _Mark> winners) {
    var index = _runIndexAt(at);
    if (index < runs.length && runs[index].start < at) {
      final run = runs[index];
      runs.insert(index + 1, run.slice(at, run.end));
      run.end = at;
      index++;
    }
    for (var i = index; i < runs.length; i++) {
      runs[i]
        ..start += count
        ..end += count;
    }
    runs.insert(index, _ResolvedRun.of(at, at + count, winners));
    if (index + 1 < runs.length && runs[index].sameWinners(runs[index + 1])) {
      runs[index].end = runs.removeAt(index + 1).end;
    }
    if (index > 0 && runs[index - 1].sameWinners(runs[index])) {
      runs[index - 1].end = runs.removeAt(index).end;
    }
  }

  // Takes out the places a delete [delta] removes.
  void remove(SequenceDelta<String> delta) {
    final cuts = <(int, int)>[];
    var cursor = 0;
    for (final op in delta.ops) {
      if (op is SeqDelete<String>) {
        cuts.add((cursor, cursor + op.count));
        cursor += op.count;
      } else if (op is SeqRetain<String>) {
        cursor += op.count;
      }
    }

    var cut = 0;
    var removed = 0;
    int moved(int at) {
      while (cut < cuts.length && cuts[cut].$2 <= at) {
        removed += cuts[cut].$2 - cuts[cut].$1;
        cut++;
      }
      if (cut < cuts.length && cuts[cut].$1 < at) {
        return cuts[cut].$1 - removed;
      }
      return at - removed;
    }

    final low = _runIndexAt(cuts.first.$1);
    final reach = cuts.last.$2;
    var kept = low;
    for (var i = low; i < runs.length; i++) {
      final run = runs[i];
      final start = moved(run.start);
      final end = moved(run.end);
      if (start == end) {
        continue;
      }
      if (run.start <= reach && kept > 0 && runs[kept - 1].sameWinners(run)) {
        runs[kept - 1].end = end;
        continue;
      }
      runs[kept++] = run
        ..start = start
        ..end = end;
    }
    runs.length = kept;
  }

  // The first run that ends after [index].
  int _runIndexAt(int index) {
    var low = 0;
    var high = runs.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (runs[middle].end <= index) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  Map<String, Object?> attributesAt(int index) {
    final at = _runIndexAt(index);
    return at < runs.length ? runs[at].attributes : const {};
  }

  List<({int start, int end, Map<String, Object?> attributes})> runsIn(
    int from,
    int to,
  ) {
    final result = <({int start, int end, Map<String, Object?> attributes})>[];
    var start = from;
    var end = from;
    Map<String, Object?>? attributes;
    for (var i = _runIndexAt(from); i < runs.length; i++) {
      final run = runs[i];
      if (run.start >= to) {
        break;
      }
      final runEnd = run.end > to ? to : run.end;
      if (attributes != null && sameAttributes(attributes, run.attributes)) {
        end = runEnd;
        continue;
      }
      if (attributes != null) {
        result.add((start: start, end: end, attributes: attributes));
      }
      start = run.start < from ? from : run.start;
      end = runEnd;
      attributes = run.attributes;
    }
    if (attributes != null) {
      result.add((start: start, end: end, attributes: attributes));
    }
    return result;
  }

  List<({int end, Object? value})> keyRuns(String key, int from, int to) {
    final result = <({int end, Object? value})>[];
    for (final run in runsIn(from, to)) {
      final value = run.attributes[key];
      if (result.isNotEmpty && result.last.value == value) {
        result[result.length - 1] = (end: run.end, value: value);
      } else {
        result.add((end: run.end, value: value));
      }
    }
    return result;
  }

  bool isRedundant(int from, int to, String key, Object? value) {
    for (var i = _runIndexAt(from); i < runs.length; i++) {
      final run = runs[i];
      if (run.start >= to) {
        break;
      }
      if (run.attributes[key] != value) {
        return false;
      }
    }
    return true;
  }
}
