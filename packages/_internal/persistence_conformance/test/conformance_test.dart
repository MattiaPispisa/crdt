@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// The clause each storage of `broken_storages.dart` has to make fail.
///
/// One entry per break. Together they are the claim this file makes: every
/// clause of the suite has teeth, because a storage that breaks it goes red.
const _mustFail = <String, List<String>>{
  'loses the last change of a batch': [
    'saveChanges stores the whole batch',
  ],
  'gives the payload bytes back empty': [
    'round-trips a change, payload bytes included',
  ],
  'says it deleted a change that was gone': [
    'deleteChange answers true, then false',
  ],
  'counts a delete that removed nothing': [
    'deleteChanges counts only what was there',
  ],
  'ignores the version bounds': [
    'newerThan keeps only what the vector has not seen',
    'upTo keeps only what the vector has seen',
    'the two together keep what sits between them',
    'a peer the vector never heard of is newer than it',
  ],
  'clears nothing': [
    'clear empties the storage',
  ],
  'gives the snapshot bytes back empty': [
    'round-trips a snapshot, state bytes included',
  ],
  'holds every snapshot id there is': [
    'containsSnapshot reflects presence',
  ],
  'forgets the identity it was given': [
    'round-trips the stored id',
  ],
  'suspends on every read': [
    'reads answer without suspending',
  ],
  'lists no document': [
    'a document is listed once something of it is stored',
  ],
  'deletes every document at once': [
    'deleteDocument leaves the other documents alone',
  ],
  'hands one storage to every document': [
    'the storage of a document is scoped to that document',
  ],
};

void main() {
  late _Run run;

  setUpAll(() async {
    run = await _runBrokenStorages();
  });

  group(
    'the conformance suite fails on a storage that breaks the contract',
    () {
      test('the broken suite ran, and did not pass', () {
        expect(
          run.total,
          greaterThan(300),
          reason: 'the whole suite runs once per broken storage',
        );
        expect(run.exitCode, isNot(0));
        expect(
          run.failed.length * 2,
          lessThan(run.total),
          reason: 'each storage breaks one clause, not the whole contract',
        );
      });

      _mustFail.forEach((storage, clauses) {
        for (final clause in clauses) {
          test('"$storage" makes "$clause" fail', () {
            expect(
              run.failed.where(
                (name) => name.startsWith(storage) && name.endsWith(clause),
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

/// What one run of `broken_storages.dart` reported.
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

/// Runs the broken storages once and reads the JSON reporter back.
///
/// One process for every storage: the suite is in memory, so the whole run
/// costs about as much as starting `dart test` does.
Future<_Run> _runBrokenStorages() async {
  final process = await Process.run(
    Platform.resolvedExecutable,
    ['test', '--reporter=json', 'test/broken_storages.dart'],
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
