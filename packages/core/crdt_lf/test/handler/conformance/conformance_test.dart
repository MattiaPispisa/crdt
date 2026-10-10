@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// The clauses each handler of `broken_handlers.dart` has to make fail.
///
/// Together they are the claim this file makes: every clause of the suite
/// goes red on a handler that breaks it.
const _mustFail = <String, List<String>>{
  'remembers a value it never held': [
    'an empty handler survives a snapshot',
  ],
  'forgets what it holds': [
    'a snapshot restores the value on a fresh peer',
    'a peer that is behind merges a snapshot to its value',
  ],
  'folds nothing in': [
    'the folded value equals a value computed from scratch',
    'a peer folding remote changes reads what a replay reads',
  ],
  'claims an order it does not have': [
    'two peers syncing every round agree with a replay',
    'every causal arrival order gives the same value',
  ],
  'snapshots without tags': [
    'a snapshot plus the changes after it reads as the history',
    'edits after a reload converge with a full-history peer',
  ],
  'compacts away an insert': [
    'a walk in transactions leaves the value of the same walk',
  ],
  'needs a live document': [
    'each cursor reads the value recorded after that change',
  ],
  'reports no change': [
    'the deltas of a local walk rebuild the value',
    'the deltas of remote changes rebuild the value',
    'the deltas of two peers editing at once rebuild each value',
  ],
  'cannot undo': [
    'undo walks back every step, redo walks forward again',
  ],
};

void main() {
  late _Run run;

  setUpAll(() async {
    run = await _runBrokenHandlers();
  });

  group(
    'the conformance suite fails on a handler that breaks the contract',
    () {
      test('the broken suite ran, and did not pass', () {
        expect(
          run.total,
          greaterThan(100),
          reason: 'the whole suite runs once per broken handler',
        );
        expect(run.exitCode, isNot(0));
        expect(
          run.failed.length * 2,
          lessThan(run.total),
          reason: 'each handler breaks one part, not the whole contract',
        );
      });

      _mustFail.forEach((handler, clauses) {
        for (final clause in clauses) {
          test('"$handler" makes "$clause" fail', () {
            expect(
              run.failed.where(
                (name) => name.startsWith(handler) && name.endsWith(clause),
              ),
              hasLength(1),
              reason: 'a clause that stays green here checks nothing',
            );
          });
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

/// What one run of `broken_handlers.dart` reported.
class _Run {
  _Run({
    required this.exitCode,
    required this.total,
    required this.failed,
  });

  /// What the `dart test` process answered.
  final int exitCode;

  /// How many tests it ran.
  final int total;

  /// The full names of the tests that did not pass.
  final Set<String> failed;
}

/// Runs the broken handlers once and reads the JSON reporter back.
Future<_Run> _runBrokenHandlers() async {
  final process = await Process.run(
    Platform.resolvedExecutable,
    [
      'test',
      '--reporter=json',
      'test/handler/conformance/broken_handlers.dart',
    ],
  );

  final names = <int, String>{};
  final failed = <String>{};

  for (final line in const LineSplitter().convert(process.stdout as String)) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (decoded is! Map<String, dynamic>) {
      continue;
    }

    switch (decoded['type']) {
      case 'testStart':
        final test = decoded['test'] as Map<String, dynamic>;
        names[test['id'] as int] = test['name'] as String;
      case 'testDone':
        if (decoded['hidden'] == true || decoded['result'] == 'success') {
          continue;
        }
        final name = names[decoded['testID'] as int];
        if (name != null) {
          failed.add(name);
        }
    }
  }

  return _Run(
    exitCode: process.exitCode,
    total: names.length,
    failed: failed,
  );
}
