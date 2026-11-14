// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';

import 'package:editor_conformance/editor_conformance.dart';
import 'package:flutter_test/flutter_test.dart';

import 'reference_editor.dart';

const _suite = ' conforms to the editor suite ';

const _timeout = Timeout(Duration(minutes: 5));

/// The clauses each editor of `broken_editors.dart` has to make fail.
///
/// Together they are the claim this file makes: every clause of the suite has
/// teeth, because an editor that breaks it goes red.
const _mustFail = <String, List<String>>{
  'never writes a deletion': [
    'local edits reach the handler',
  ],
  'counts code units as runes': [
    'an emoji is one position of the handler',
    'the caret moves by code units past an emoji',
    'a selection publishes its anchors, in runes',
  ],
  'rebuilds on a remote change': [
    'a remote insert shows without a rebuild, caret kept',
  ],
  'leaves the caret at its offset on a remote change': [
    'a batch of remote changes keeps the caret at the end',
    'an anchor survives a remote insert before it',
    'remote embed changes show, caret kept',
  ],
  'shifts the caret by how much the text grew': [
    'a change at both ends does not drag the caret',
  ],
  'ignores a remote change that shortens the text': [
    'a remote replacement keeps the caret at the end',
    'a remote deletion shows',
    'a random stream of edits keeps editor and handler equal',
  ],
  'remembers what it shows in one place for every editor': [
    'two editors follow each other',
  ],
  'ignores the deletion of its handler': [
    'a deleted handler shows the deleted builder',
  ],
  'binds a handler of any type': [
    'another handler type is refused',
  ],
  'publishes anchors without the focus': [
    'nothing is published without the focus',
    'a blur withdraws the anchors, once',
  ],
  'does not publish after its own edit': [
    'a local edit moves the anchors',
  ],
  'publishes on every remote change': [
    'a batch of remote changes publishes no stale anchor',
  ],
  'commits while composing': [
    'nothing is committed while a composition is active',
  ],
  'drops the pending composition on a remote change': [
    'a remote change keeps the pending composition',
  ],
  'commits a composition at its old index': [
    'an insert at its start',
    'an insert inside it',
    'an embed at its start',
    'an embed inside it',
  ],
  'skips an embed when it counts positions': [
    'edits around an embed keep it',
  ],
  'writes a typed U+FFFC': [
    'a typed U+FFFC is not written, the rest is',
  ],
  'stops following after a write made inside its own': [
    'is taken in: text',
    'is taken in: format',
    'is taken in: embed update',
  ],
  'keeps its anchors during a composition': [
    'anchors are withdrawn while a composition is pending',
  ],
  'maps the caret through an undo like a remote change': [
    'undo and redo take back a local edit, caret after it',
  ],
  'writes without its origin': [
    'only the writes of the editor are recorded',
  ],
  'undoes with its own text history': [
    'a peer edit is not undone, and it survives the undo',
    'undo brings a deleted embed back with its data',
  ],
  'moves the caret on an undo that changes nothing': [
    'an undo that changes nothing leaves the caret',
  ],
  'formats inside the typing step': [
    'a format is a step of its own, apart from the typing',
  ],
};

void main() {
  runEditorConformanceTests('the reference editor', ReferenceHarness.new);

  group('the conformance suite fails on an editor that breaks the contract',
      () {
    // One run for every test of the group, started by the first one.
    late final broken = _runBrokenEditors();

    test(
      'the broken suite ran, and did not pass',
      () async {
        final run = await broken;
        expect(run.exitCode, isNot(0));
        expect(run.editors, _mustFail.keys.toSet());
        expect(
          run.failed.length * 2,
          lessThan(run.total),
          reason: 'each editor breaks one rule, not the whole contract',
        );
      },
      timeout: _timeout,
    );

    test(
      'every clause has an editor that breaks it',
      () async {
        final run = await broken;
        final covered = _mustFail.values.expand((clauses) => clauses);
        expect(
          run.clauses.where((clause) => !covered.any(clause.endsWith)),
          isEmpty,
          reason: 'a clause no broken editor fails may check nothing',
        );
      },
      timeout: _timeout,
    );

    _mustFail.forEach((editor, clauses) {
      for (final clause in clauses) {
        test(
          '"$editor" makes "$clause" fail',
          () async {
            final run = await broken;
            expect(
              run.failed.where(
                (name) => name.startsWith(editor) && name.endsWith(clause),
              ),
              hasLength(1),
              reason: 'a clause that stays green here checks nothing',
            );
          },
          timeout: _timeout,
        );
      }
    });
  });
}

/// What one run of `broken_editors.dart` reported.
class _Run {
  _Run({
    required this.exitCode,
    required this.names,
    required this.failed,
  });

  /// What the `flutter test` process answered.
  final int exitCode;

  /// The full names of the suite tests it ran.
  final Set<String> names;

  /// The full names of the ones that did not pass.
  final Set<String> failed;

  int get total => names.length;

  /// The broken editors the suite ran on.
  Set<String> get editors => {
        for (final name in names) name.substring(0, name.indexOf(_suite)),
      };

  /// The clauses of the suite, with their groups.
  Set<String> get clauses => {
        for (final name in names)
          name.substring(name.indexOf(_suite) + _suite.length),
      };
}

/// Runs the broken editors once and reads the JSON reporter back.
Future<_Run> _runBrokenEditors() async {
  final process = await Process.run(
    '${Platform.environment['FLUTTER_ROOT']}/bin/flutter',
    ['test', '--no-pub', '--reporter=json', 'test/broken_editors.dart'],
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
        final name = test['name'] as String;
        if (name.contains(_suite)) {
          names[test['id'] as int] = name;
        }
      case 'testDone':
        if (decoded['result'] == 'success') {
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
    names: names.values.toSet(),
    failed: failed,
  );
}
